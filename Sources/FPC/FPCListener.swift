/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Foundation
import Descriptors
import Capabilities

// MARK: - FPCListener

/// An FPC listener backed by a BSD Unix-domain SEQPACKET socket.
///
/// This listener is specifically designed for SOCK_SEQPACKET which provides:
/// - Connection-oriented communication (listen/accept like STREAM)
/// - FPCMessage boundary preservation (like DATAGRAM)
/// - Reliable, ordered delivery
///
/// Obtain an instance via ``listen(on:)``. After calling ``start()``,
/// iterate over ``connections()`` to receive newly accepted ``FPCEndpoint``
/// instances, or call ``accept()`` to handle one connection at a time.
public actor FPCListener {
    private let socketHolder: SocketHolder
    private let ioQueue: DispatchQueue
    private var state: LifecycleState = .idle
    private var connectionStream: AsyncThrowingStream<FPCEndpoint, Error>?
    private var connectionContinuation: AsyncThrowingStream<FPCEndpoint, Error>.Continuation?
    private var acceptLoopTask: Task<Void, Never>?

    // MARK: - Listen

    /// Begins listening on a Unix-domain SEQPACKET socket at the given path.
    ///
    /// - Parameters:
    ///   - path: The filesystem path at which to bind the socket.
    ///   - backlog: Maximum length of the pending connection queue (default: 128)
    ///   - ioQueue: Optional custom DispatchQueue for I/O operations. If `nil`, a default queue is created.
    /// - Returns: A new, unstarted ``FPCListener``. Call ``start()`` before use.
    /// - Throws: A system error if the socket cannot be created or bound.
    public static func listen(
        on path: String,
        backlog: Int32 = 128,
        ioQueue: DispatchQueue? = nil
    ) throws -> FPCListener {
        let socket = try SocketCapability.socket(
            domain: .unix,
            type: [.seqpacket, .cloexec],
            protocol: .default
        )
        let address = try UnixSocketAddress(path: path)
        try socket.bind(address: address)
        try socket.listen(backlog: backlog)
        return FPCListener(socket: socket, ioQueue: ioQueue)
    }

    /// Begins listening on a Unix-domain SEQPACKET socket at a path relative to a directory.
    ///
    /// This uses `bindat(2)` to bind the socket relative to a directory descriptor.
    /// This is useful in Capsicum sandboxes where you have a capability for the
    /// directory but cannot use absolute paths.
    ///
    /// - Parameters:
    ///   - directory: A directory descriptor to use as the base for the path.
    ///   - path: The relative path within the directory at which to bind the socket.
    ///   - backlog: Maximum length of the pending connection queue (default: 128)
    ///   - ioQueue: Optional custom DispatchQueue for I/O operations. If `nil`, a default queue is created.
    /// - Returns: A new, unstarted ``FPCListener``. Call ``start()`` before use.
    /// - Throws: A system error if the socket cannot be created or bound.
    public static func listen<D: DirectoryDescriptor>(
        at directory: borrowing D,
        path: String,
        backlog: Int32 = 128,
        ioQueue: DispatchQueue? = nil
    ) throws -> FPCListener where D: ~Copyable {
        let socket = try SocketCapability.socket(
            domain: .unix,
            type: [.seqpacket, .cloexec],
            protocol: .default
        )
        let address = try UnixSocketAddress(path: path)
        try socket.bind(at: directory, address: address)
        try socket.listen(backlog: backlog)
        return FPCListener(socket: socket, ioQueue: ioQueue)
    }

    /// Creates a listener from an already-listening socket.
    ///
    /// Use this when you receive a listening socket via descriptor passing,
    /// socket activation, or other external mechanisms.
    ///
    /// - Parameters:
    ///   - socket: An already-bound and listening socket
    ///   - ioQueue: Optional custom DispatchQueue for I/O operations
    /// - Returns: A new, unstarted ``FPCListener``. Call ``start()`` before use.
    public init(socket: consuming SocketCapability, ioQueue: DispatchQueue? = nil) {
        self.socketHolder = SocketHolder(socket: socket)
        self.ioQueue = ioQueue ?? DispatchQueue(label: "com.fpc.listener.io", qos: .userInitiated)
    }

    // MARK: Lifecycle

    public func start() {
        guard state == .idle else { return }
        state = .running
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: FPCEndpoint.self)
        connectionStream = stream
        connectionContinuation = continuation

        acceptLoopTask = Task {
            do {
                while state == .running {
                    let endpoint = try await accept()
                    connectionContinuation?.yield(endpoint)
                }
                connectionContinuation?.finish()
            } catch {
                connectionContinuation?.finish(throwing: error)
            }
        }
    }

    public func stop() {
        guard state != .stopped else { return }
        state = .stopped
        acceptLoopTask?.cancel()
        acceptLoopTask = nil
        socketHolder.close()
        connectionContinuation?.finish()
        connectionContinuation = nil
    }

    // MARK: - Public API

    /// Returns the stream of incoming connections.
    ///
    /// Can only be claimed by one task. Throws `.notStarted` if ``start()`` has not been
    /// called, `.listenerClosed` if ``stop()`` has been called, or `.streamAlreadyClaimed`
    /// if already claimed.
    public func connections() throws -> AsyncThrowingStream<FPCEndpoint, Error> {
        switch state {
        case .idle:    throw FPCError.notStarted
        case .stopped: throw FPCError.listenerClosed
        case .running: break
        }
        guard let stream = connectionStream else {
            throw FPCError.streamAlreadyClaimed
        }
        connectionStream = nil
        return stream
    }

    /// Accepts the next incoming connection. Suspends until a client connects.
    ///
    /// The accepted socket is configured with `LOCAL_CREDS_PERSISTENT` to enable
    /// per-message credential delivery via `SCM_CREDS2`.
    ///
    /// - Throws: ``FPCError/listenerClosed`` if the listener has been stopped.
    public func accept() async throws -> FPCEndpoint {
        guard state == .running else { throw FPCError.listenerClosed }

        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    guard let clientSocket = try self.socketHolder.withSocket({ socket in
                        try socket.accept()
                    }) else {
                        continuation.resume(throwing: FPCError.listenerClosed)
                        return
                    }

                    // Enable persistent credentials for per-message credential delivery
                    try clientSocket.enablePersistentCredentials()

                    continuation.resume(returning: FPCEndpoint(socket: clientSocket))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
