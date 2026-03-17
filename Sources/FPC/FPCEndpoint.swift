/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Foundation
import Glibc
import FreeBSDKit
import Descriptors
import Capabilities
import Capsicum

// MARK: - FPCEndpoint

/// An ``Endpoint`` backed by a BSD Unix-domain SEQPACKET socket.
///
/// This endpoint is specifically designed for SOCK_SEQPACKET which provides:
/// - Connection-oriented communication (like STREAM)
/// - FPCMessage boundary preservation (like DATAGRAM)
/// - Reliable, ordered delivery
///
/// Obtain an instance via ``FPCClient`` or ``pair()``.
/// After calling ``start()``, use ``send(_:)`` and ``request(_:)`` to write
/// to the wire, and ``incoming()`` to consume inbound messages.
public actor FPCEndpoint: Endpoint {
    private let socketHolder: SocketHolder
    private let ioQueue: DispatchQueue
    private var nextCorrelationID: UInt64 = 1
    private var pendingReplies: [UInt64: CheckedContinuation<FPCMessage, Error>] = [:]
    private var pendingTimeouts: [UInt64: Task<Void, Never>] = [:]
    private var incomingContinuation: AsyncStream<FPCMessage>.Continuation?
    private var incomingStream: AsyncStream<FPCMessage>?
    private var receiveLoopTask: Task<Void, Never>?
    private var state: LifecycleState = .idle

    // MARK: Init

    public init(socket: consuming SocketCapability, ioQueue: DispatchQueue? = nil) {
        self.socketHolder = SocketHolder(socket: socket)
        // IMPORTANT: Must be concurrent so send() doesn't block behind receive loop
        self.ioQueue = ioQueue ?? DispatchQueue(label: "com.fpc.endpoint.io", qos: .userInitiated, attributes: .concurrent)
    }

    // MARK: - Connection State

    public var connectionState: ConnectionState {
        state
    }

    // MARK: - Peer Credentials

    /// Gets the credentials of the peer connected to this endpoint.
    ///
    /// Uses the `LOCAL_PEERCRED` socket option to retrieve the peer's credentials.
    /// For server-side endpoints (from `accept()`), this returns the client's credentials.
    /// For client-side endpoints, this returns the server's credentials at `listen()` time.
    ///
    /// - Returns: The credentials of the connected peer.
    /// - Throws: ``FPCError/disconnected`` if the socket is closed,
    ///           or a BSD error if credentials cannot be retrieved.
    public func getPeerCredentials() throws -> PeerCredentials {
        try socketHolder.withSocketOrThrow { socket in
            try socket.getPeerCredentials()
        }
    }

    // MARK: Lifecycle

    public func start() {
        guard state == .idle else { return }
        state = .running
        let (stream, continuation) = AsyncStream.makeStream(of: FPCMessage.self)
        incomingStream = stream
        incomingContinuation = continuation

        receiveLoopTask = Task {
            await receiveLoop()
        }
    }

    public func stop() {
        guard state != .stopped else { return }
        state = .stopped
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        socketHolder.close()
        teardown(throwing: FPCError.stopped)
    }

    // MARK: - Public API

    /// Sends a fire-and-forget message. Suspends until the bytes are on the wire.
    public func send(_ message: FPCMessage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async {
                do {
                    try self.socketSend(message)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sends a message and suspends until the matching reply arrives.
    ///
    /// A correlation ID is assigned automatically; the `correlationID` field of
    /// `message` is overwritten before sending.
    ///
    /// - Parameters:
    ///   - message: The request message to send
    ///   - timeout: Optional timeout duration. If `nil`, waits indefinitely. If provided and exceeded, throws ``FPCError/timeout``
    /// - Returns: The reply message with matching correlation ID
    /// - Throws: ``FPCError/timeout`` if timeout is specified and exceeded
    public func request(_ message: FPCMessage, timeout: Duration? = nil) async throws -> FPCMessage {
        // 64-bit correlation ID - won't wrap in practice (~585 years at 1B msg/sec)
        let correlationID = nextCorrelationID
        nextCorrelationID += 1
        // Skip 0 (reserved for unsolicited messages)
        if nextCorrelationID == 0 { nextCorrelationID = 1 }

        var outgoing = message
        outgoing.correlationID = correlationID

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Register continuation BEFORE sending to avoid lost-reply race
                pendingReplies[correlationID] = continuation

                // Start a timeout task if timeout is specified
                if let timeout = timeout {
                    let timeoutTask = Task { [correlationID] in
                        try? await Task.sleep(for: timeout)
                        await self.handleTimeout(correlationID)
                    }
                    pendingTimeouts[correlationID] = timeoutTask
                }

                // Check for early cancellation before sending
                if Task.isCancelled {
                    Task { await self.failPendingRequest(correlationID, error: CancellationError()) }
                    return
                }

                // Send in background task; clean up on failure
                Task {
                    do {
                        try await self.send(outgoing)
                    } catch {
                        await self.failPendingRequest(correlationID, error: error)
                    }
                }
            }
        } onCancel: {
            Task { await self.failPendingRequest(correlationID, error: CancellationError()) }
        }
    }

    /// Sends a reply to a previously received request.
    ///
    /// Automatically copies the correlation ID from the original request message.
    /// This ensures the reply is routed back to the caller waiting in `request()`.
    public func reply(
        to request: FPCMessage,
        id: MessageID,
        payload: Data = Data(),
        descriptors: [OpaqueDescriptorRef] = []
    ) async throws {
        let replyMessage = FPCMessage(
            id: id,
            correlationID: request.correlationID,
            payload: payload,
            descriptors: descriptors
        )
        try await send(replyMessage)
    }

    /// Sends a reply using a reply token from a previously received request.
    ///
    /// Use this when you don't want to keep the entire message around:
    ///
    /// ```swift
    /// let request = try await endpoint.receive()
    /// let token = request.replyToken
    /// // ... process request ...
    /// try await endpoint.reply(to: token, id: .pong, payload: data)
    /// ```
    public func reply(
        to token: FPCReplyToken,
        id: MessageID,
        payload: Data = Data(),
        descriptors: [OpaqueDescriptorRef] = []
    ) async throws {
        let replyMessage = FPCMessage(
            id: id,
            correlationID: token.correlationID,
            payload: payload,
            descriptors: descriptors
        )
        try await send(replyMessage)
    }

    /// Returns the stream of unsolicited inbound messages (correlationID == 0).
    ///
    /// Reply messages (correlationID != 0) are automatically routed to the
    /// corresponding ``request(_:timeout:)`` caller and never appear here.
    ///
    /// Can only be claimed by one task. Throws `.notStarted` if ``start()`` has
    /// not been called, `.stopped` if ``stop()`` has been called, or
    /// `.streamAlreadyClaimed` if already claimed.
    public func incoming() throws -> AsyncStream<FPCMessage> {
        switch state {
        case .idle:    throw FPCError.notStarted
        case .stopped: throw FPCError.stopped
        case .running: break
        }
        guard let stream = incomingStream else {
            throw FPCError.streamAlreadyClaimed
        }
        incomingStream = nil
        return stream
    }

    // MARK: - Pair

    /// Creates a pair of connected ``FPCEndpoint`` instances using `socketpair(2)`.
    ///
    /// The returned endpoints are bidirectionally connected SEQPACKET sockets ready
    /// for local IPC. Both are unstarted; call ``start()`` on each before exchanging
    /// messages.
    ///
    /// Each endpoint gets its own independent I/O queue to avoid serialization bottlenecks
    /// and potential deadlocks when the endpoints communicate with each other.
    ///
    /// Both sockets are configured with `LOCAL_CREDS_PERSISTENT` to enable per-message
    /// credential delivery via `SCM_CREDS2`.
    ///
    /// - Parameters:
    ///   - firstQueue: Optional custom DispatchQueue for the first endpoint's I/O operations.
    ///                 If `nil`, a default queue is created.
    ///   - secondQueue: Optional custom DispatchQueue for the second endpoint's I/O operations.
    ///                  If `nil`, a default queue is created.
    /// - Returns: A tuple of two connected SEQPACKET endpoints, each with its own I/O queue.
    /// - Throws: A system error if the socketpair cannot be created.
    public static func pair(
        firstQueue: DispatchQueue? = nil,
        secondQueue: DispatchQueue? = nil
    ) throws -> (FPCEndpoint, FPCEndpoint) {
        let socketPair = try SocketCapability.socketPair(
            domain: .unix,
            type: [.seqpacket, .cloexec],
            protocol: .default
        )

        // Enable persistent credentials for per-message credential delivery on both ends
        try socketPair.first.enablePersistentCredentials()
        try socketPair.second.enablePersistentCredentials()

        return (FPCEndpoint(socket: socketPair.first, ioQueue: firstQueue),
                FPCEndpoint(socket: socketPair.second, ioQueue: secondQueue))
    }

    // MARK: - Private

    private func handleTimeout(_ correlationID: UInt64) async {
        pendingTimeouts.removeValue(forKey: correlationID)
        if let pending = pendingReplies.removeValue(forKey: correlationID) {
            pending.resume(throwing: FPCError.timeout)
        }
    }

    private func failPendingRequest(_ correlationID: UInt64, error: Error) async {
        if let timeoutTask = pendingTimeouts.removeValue(forKey: correlationID) {
            timeoutTask.cancel()
        }
        if let pending = pendingReplies.removeValue(forKey: correlationID) {
            pending.resume(throwing: error)
        }
    }

    /// Routes an incoming message to a waiting `request()` caller or the unsolicited stream.
    ///
    /// Messages with `correlationID != 0` are checked against pending requests:
    /// - If a matching pending request exists, it's a reply - route to the caller
    /// - If no pending request exists, it's an incoming request - route to messages() stream
    ///
    /// Messages with `correlationID == 0` are always unsolicited and go to messages().
    private func dispatch(_ message: FPCMessage) {
        if message.correlationID != 0 {
            // Check if this is a reply to a pending request we sent
            if let continuation = pendingReplies.removeValue(forKey: message.correlationID) {
                // It's a reply - cancel timeout and deliver to caller
                if let timeoutTask = pendingTimeouts.removeValue(forKey: message.correlationID) {
                    timeoutTask.cancel()
                }
                continuation.resume(returning: message)
            } else {
                // No pending request - this is an incoming request expecting a reply
                // Deliver to messages() stream so the handler can process and reply
                incomingContinuation?.yield(message)
            }
        } else {
            // Unsolicited message (correlationID == 0)
            incomingContinuation?.yield(message)
        }
    }

    private func receiveLoop() async {
        defer {
            // Ensure cleanup if loop exits unexpectedly
            if state == .running {
                state = .stopped
                socketHolder.close()
                teardown(throwing: FPCError.disconnected)
            }
        }

        while !Task.isCancelled {
            do {
                let message = try await receiveFromSocket()
                dispatch(message)
            } catch {
                state = .stopped
                socketHolder.close()
                teardown(throwing: error)
                break
            }
        }
    }

    /// Suspends until one complete message arrives on the socket.
    /// Blocking I/O is pushed off the cooperative thread pool onto `ioQueue`.
    private func receiveFromSocket() async throws -> FPCMessage {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let message = try self.socketReceive()
                    continuation.resume(returning: message)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fails all suspended callers and closes the unsolicited message stream.
    private func teardown(throwing error: Error) {
        // Cancel all pending timeout tasks
        for (_, task) in pendingTimeouts {
            task.cancel()
        }
        pendingTimeouts.removeAll()

        // Fail all pending replies
        for (_, continuation) in pendingReplies {
            continuation.resume(throwing: error)
        }
        pendingReplies.removeAll()
        incomingContinuation?.finish()
        incomingContinuation = nil
    }

    // MARK: - Wire Format I/O
    //
    // Wire format encoding/decoding is handled by FPCFrameLayout.swift.
    // This section handles the actual socket I/O and OOL payload management.

    /// Maximum inline payload size before switching to out-of-line shared memory.
    ///
    /// Queried from the `net.local.seqpacket.maxseqpacket` sysctl. Typically 64KB
    /// on FreeBSD. Messages exceeding this limit are automatically sent via
    /// anonymous shared memory with the payload descriptor passed out-of-band.
    private static let MAX_INLINE_PAYLOAD: Int = {
        // Account for header (256) + trailer (256) in the total message
        let overhead = 512
        let kernelMax = SocketLimits.maxSeqpacketSize()

        // Payload space is kernel max minus overhead, but never negative
        // If kernel max is very small, OOL will be used for most payloads
        let available = kernelMax - overhead
        return available > 0 ? available : 0
    }()

    nonisolated private func socketSend(_ message: FPCMessage) throws {
        var payload = message.payload
        var descriptors = message.descriptors
        var useOOL = false

        // Handle out-of-line payload if needed
        var shmDescriptor: Int32? = nil
        if payload.count > Self.MAX_INLINE_PAYLOAD {
            // Check descriptor limit (254 max, OOL adds one more)
            guard descriptors.count < FPCFrameLayout.maxDescriptors else {
                throw FPCError.tooManyDescriptors(descriptors.count + 1)
            }
            // Create anonymous shared memory (capability-mode safe)
            let shm = try SharedMemoryCapability.anonymous(accessMode: .readWrite)

            // Set size and map
            try shm.setSize(payload.count)
            let region = try shm.map(
                size: payload.count,
                protection: [.read, .write],
                flags: [.shared]
            )

            // Copy payload to shared memory
            try payload.withUnsafeBytes { payloadBytes in
                guard let source = payloadBytes.baseAddress else {
                    throw POSIXError(.EINVAL)
                }
                UnsafeMutableRawPointer(mutating: region.base).copyMemory(
                    from: source,
                    byteCount: payload.count
                )
            }

            // Unmap after copying
            try region.unmap()

            // Limit to read-only rights before sending to receiver
            let readOnlyRights = CapsicumRightSet(rights: [
                .mmapR,      // Allow read-only mmap
                .fstat,      // Allow fstat to get size
                .seek        // Allow lseek for reading
            ])
            _ = shm.limit(rights: readOnlyRights)

            // Track fd for cleanup on send failure
            shmDescriptor = shm.take()
            let shmRef = OpaqueDescriptorRef(shmDescriptor!, kind: .shm)

            // Prepend OOL descriptor
            descriptors.insert(shmRef, at: 0)
            payload = Data()
            useOOL = true
        } else {
            // Validate descriptor count (254 max)
            guard descriptors.count <= FPCFrameLayout.maxDescriptors else {
                throw FPCError.tooManyDescriptors(descriptors.count)
            }
        }

        // Build wire message using FPCFrameLayout
        let header = FPCFrameHeader(
            messageID: message.id.rawValue,
            correlationID: message.correlationID,
            payloadLength: UInt32(payload.count),
            descriptorCount: UInt8(descriptors.count),
            flags: useOOL ? FPCFrameLayout.flagOOLPayload : 0
        )

        let descriptorKinds = descriptors.prefix(FPCFrameLayout.maxDescriptors).map { $0.kind.wireValue }
        let trailer = FPCFrameTrailer(descriptorKinds: Array(descriptorKinds))

        // Assemble wire data
        var wireData = header.encode()
        wireData.append(payload)
        wireData.append(trailer.encode(hasOOLPayload: useOOL))

        do {
            try socketHolder.withSocketOrThrow { socket in
                try socket.sendDescriptors(descriptors, payload: wireData)
            }
        } catch {
            // Clean up OOL descriptor if send failed
            if let fd = shmDescriptor {
                _ = Glibc.close(fd)
            }
            throw error
        }
    }

    nonisolated private func socketReceive() throws -> FPCMessage {
        // SEQPACKET guarantees message boundaries: each recv() returns exactly one message.
        // No buffering needed - the kernel preserves message atomicity.
        let maxBufferSize = FPCFrameLayout.headerSize + Self.MAX_INLINE_PAYLOAD + FPCFrameLayout.trailerSize

        let result = try socketHolder.withSocketOrThrow { socket in
            try socket.recvDescriptorsWithCredentials(
                maxDescriptors: FPCFrameLayout.maxDescriptors,
                bufferSize: maxBufferSize
            )
        }

        // Check for connection closed (0 bytes)
        guard result.data.count > 0 else {
            throw FPCError.disconnected
        }

        // Convert SocketCredentials to MessageCredentials if present
        let messageCredentials: MessageCredentials? = result.credentials.map { creds in
            MessageCredentials(
                realUID: creds.realUID,
                effectiveUID: creds.effectiveUID,
                realGID: creds.realGID,
                effectiveGID: creds.effectiveGID,
                pid: creds.pid,
                groups: creds.groups
            )
        }

        return try parseMessage(
            wireData: result.data,
            receivedDescriptors: result.descriptors,
            credentials: messageCredentials
        )
    }

    /// Parses a complete BPC message from wire data.
    nonisolated private func parseMessage(
        wireData: Data,
        receivedDescriptors: [OpaqueDescriptorRef],
        credentials: MessageCredentials? = nil
    ) throws -> FPCMessage {
        guard wireData.count >= FPCFrameLayout.minimumMessageSize else {
            throw FPCError.invalidMessageFormat
        }

        // Parse and validate header
        let header = try FPCFrameHeader.decode(from: wireData)
        try header.validate()

        // Validate total message size
        let expectedTotal = FPCFrameLayout.headerSize + Int(header.payloadLength) + FPCFrameLayout.trailerSize
        guard wireData.count == expectedTotal else {
            throw FPCError.invalidMessageFormat
        }

        // Validate descriptor count matches
        guard receivedDescriptors.count == Int(header.descriptorCount) else {
            throw FPCError.invalidMessageFormat
        }

        // Parse and validate trailer
        let trailerStart = wireData.count - FPCFrameLayout.trailerSize
        let trailerData = Data(wireData[trailerStart...])
        let trailer = try FPCFrameTrailer.decode(from: trailerData, descriptorCount: Int(header.descriptorCount))
        try trailer.validate(hasOOLPayload: header.hasOOLPayload)

        // Apply descriptor kinds from trailer
        var descriptors = receivedDescriptors
        for (index, kindValue) in trailer.descriptorKinds.enumerated() {
            guard index < descriptors.count else { break }
            if kindValue != DescriptorKind.oolPayloadWireValue {
                descriptors[index].kind = DescriptorKind.fromWireValue(kindValue)
            }
        }

        // Handle payload (inline or out-of-line)
        var payload: Data

        if header.hasOOLPayload {
            guard !descriptors.isEmpty else {
                throw FPCError.invalidMessageFormat
            }

            let shmDescriptor = descriptors.removeFirst()

            // Take ownership of the fd to ensure explicit cleanup
            guard let shmFD = shmDescriptor.take() else {
                throw FPCError.invalidMessageFormat
            }

            defer {
                Glibc.close(shmFD)
            }

            var stat = stat()
            guard Glibc.fstat(shmFD, &stat) == 0 else {
                try BSDError.throwErrno(errno)
            }

            let shmSize = Int(stat.st_size)
            guard shmSize > 0 else {
                throw FPCError.invalidMessageFormat
            }

            let ptr = Glibc.mmap(nil, shmSize, PROT_READ, MAP_SHARED, shmFD, 0)
            guard ptr != MAP_FAILED, let mappedPtr = ptr else {
                try BSDError.throwErrno(errno)
            }

            defer {
                Glibc.munmap(mappedPtr, shmSize)
            }

            payload = Data(bytes: mappedPtr, count: shmSize)
        } else {
            let payloadStart = FPCFrameLayout.headerSize
            let payloadEnd = payloadStart + Int(header.payloadLength)
            payload = Data(wireData[payloadStart..<payloadEnd])
        }

        return FPCMessage(
            id: MessageID(rawValue: header.messageID),
            correlationID: header.correlationID,
            payload: payload,
            descriptors: descriptors,
            senderCredentials: credentials
        )
    }
}
