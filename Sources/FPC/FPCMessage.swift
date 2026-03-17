/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Foundation
import Descriptors
import Capabilities
import Glibc

// MARK: - FPCReplyToken

/// A lightweight token for replying to a received message.
///
/// Instead of holding onto the entire `FPCMessage`, extract a reply token and use it later:
///
/// ```swift
/// let request = try await endpoint.receive()
/// let token = request.replyToken
///
/// // ... process request ...
///
/// try await endpoint.reply(to: token, id: .pong, payload: data)
/// ```
public struct FPCReplyToken: Sendable, Hashable {
    /// The correlation ID to echo back in the reply.
    public let correlationID: UInt64

    /// Creates a reply token with the specified correlation ID.
    public init(correlationID: UInt64) {
        self.correlationID = correlationID
    }
}

// MARK: - FPCMessage

/// A unit of communication between a BPC client and server.
///
/// Each message carries a typed identifier, an optional binary payload, and optional
/// file descriptors. Correlation IDs tie request/reply pairs together: a value of `0`
/// indicates an unsolicited message; a non-zero value links a reply to the request
/// that originated it — the correlation ID is assigned by the sending ``FPCEndpoint``.
public struct FPCMessage: Sendable {

    /// Identifies the kind of message.
    public var id: MessageID

    /// Links a reply to its originating request.
    ///
    /// `0` means the message is unsolicited. Non-zero values are assigned automatically
    /// by ``FPCEndpoint/send(_:)`` and echoed back in the matching reply.
    /// Uses 64-bit to avoid wrap-around (~585 years at 1 billion msg/sec).
    public var correlationID: UInt64

    /// The message body, interpreted by the application layer.
    public var payload: Data

    /// File descriptors delivered alongside the payload over the Unix socket.
    public var descriptors: [OpaqueDescriptorRef]

    /// Credentials of the process that sent this message.
    ///
    /// This is populated automatically when receiving messages. FPC enables
    /// `LOCAL_CREDS_PERSISTENT` on all sockets, which delivers the sender's
    /// credentials via `SCM_CREDS2` with every message.
    ///
    /// Unlike ``FPCEndpoint/getPeerCredentials()`` (which only provides effective
    /// credentials at connection time), this provides:
    /// - Real and effective UID/GID
    /// - Per-message credentials (can detect credential changes)
    /// - Setuid/setgid detection via `isSetuid`/`isSetgid`
    ///
    /// - Note: This is `nil` for locally-constructed messages that
    ///   haven't been received from a socket.
    ///
    /// ## Example
    ///
    /// ```swift
    /// for await message in endpoint.incoming() {
    ///     if let creds = message.senderCredentials {
    ///         print("From PID \(creds.pid), real UID \(creds.realUID)")
    ///         if creds.isSetuid {
    ///             print("Warning: setuid process")
    ///         }
    ///     }
    /// }
    /// ```
    public let senderCredentials: MessageCredentials?

    /// Creates a message with explicit field values.
    public init(
        id: MessageID,
        correlationID: UInt64 = 0,
        payload: Data = Data(),
        descriptors: [OpaqueDescriptorRef] = [],
        senderCredentials: MessageCredentials? = nil
    ) {
        self.id = id
        self.correlationID = correlationID
        self.payload = payload
        self.descriptors = descriptors
        self.senderCredentials = senderCredentials
    }

    /// Returns a lightweight token for replying to this message.
    ///
    /// Use this when you don't want to keep the entire message around:
    ///
    /// ```swift
    /// let request = try await endpoint.receive()
    /// let token = request.replyToken
    /// // Can discard the original request now
    /// try await endpoint.reply(to: token, id: .pong)
    /// ```
    public var replyToken: FPCReplyToken {
        FPCReplyToken(correlationID: correlationID)
    }

    /// Creates a message intended for a request/reply exchange.
    ///
    /// The sending ``FPCEndpoint`` assigns the correlation ID automatically;
    /// leave it at the default `0`.
    ///
    /// This can also be used for one-way messages that don't expect a reply.
    public static func request(
        _ id: MessageID,
        payload: Data = Data(),
        descriptors: [OpaqueDescriptorRef] = []
    ) -> FPCMessage {
        FPCMessage(id: id, correlationID: 0, payload: payload, descriptors: descriptors)
    }

    /// Creates a reply to a previously received request.
    ///
    /// Automatically copies the correlation ID from the original request to ensure
    /// proper routing. Use this when manually constructing reply messages.
    ///
    /// - Parameters:
    ///   - request: The original request message to reply to
    ///   - id: The message ID for the reply (e.g., `.lookupReply`, `.pong`)
    ///   - payload: Optional payload data for the reply
    ///   - descriptors: Optional file descriptors to send with the reply
    /// - Returns: A message with the same correlation ID as the request
    public static func reply(
        to request: FPCMessage,
        id: MessageID,
        payload: Data = Data(),
        descriptors: [OpaqueDescriptorRef] = []
    ) -> FPCMessage {
        FPCMessage(
            id: id,
            correlationID: request.correlationID,
            payload: payload,
            descriptors: descriptors
        )
    }

    /// Creates a reply using a reply token from a previously received request.
    ///
    /// Useful when you don't want to keep the entire message around:
    ///
    /// ```swift
    /// let request = try await endpoint.receive()
    /// let token = request.replyToken
    /// // ... later ...
    /// let reply = FPCMessage.reply(to: token, id: .pong)
    /// try await endpoint.send(reply)
    /// ```
    ///
    /// - Parameters:
    ///   - token: Reply token extracted from the original request
    ///   - id: The message ID for the reply
    ///   - payload: Optional payload data for the reply
    ///   - descriptors: Optional file descriptors to send with the reply
    /// - Returns: A message with the correlation ID from the token
    public static func reply(
        to token: FPCReplyToken,
        id: MessageID,
        payload: Data = Data(),
        descriptors: [OpaqueDescriptorRef] = []
    ) -> FPCMessage {
        FPCMessage(
            id: id,
            correlationID: token.correlationID,
            payload: payload,
            descriptors: descriptors
        )
    }

    // MARK: - Descriptor Extraction

    /// Returns the raw file descriptor value at the specified index.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: The raw file descriptor if it exists and is valid, otherwise `nil`
    public func descriptor(at index: Int = 0) -> Int32? {
        guard index < descriptors.count else { return nil }
        return descriptors[index].toBSDValue()
    }

    /// Returns the descriptor kind at the specified index.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: The descriptor kind if it exists, otherwise `nil`
    public func descriptorKind(at index: Int = 0) -> DescriptorKind? {
        guard index < descriptors.count else { return nil }
        return descriptors[index].kind
    }

    /// Extracts a descriptor of a specific kind from the message.
    ///
    /// Returns the raw file descriptor if the descriptor at the given index matches the expected kind.
    ///
    /// ```swift
    /// // Extract a file descriptor
    /// if let fd = message.descriptor(at: 0, expecting: .file) {
    ///     let file = FileCapability(fd)
    /// }
    ///
    /// // Extract a socket descriptor
    /// if let fd = message.descriptor(at: 1, expecting: .socket) {
    ///     let socket = SocketCapability(fd)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - index: The index of the descriptor (default: 0)
    ///   - kind: The expected descriptor kind
    /// - Returns: The raw file descriptor if it exists and matches the expected kind, otherwise `nil`
    public func descriptor(at index: Int = 0, expecting kind: DescriptorKind) -> Int32? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == kind else { return nil }
        return descriptors[index].toBSDValue()
    }

    /// Extracts a file descriptor from the message, transferring ownership to the caller.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned capability owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: A `FileCapability` if the descriptor exists and is a file, otherwise `nil`
    public mutating func fileDescriptor(at index: Int = 0) -> FileCapability? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .file else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return FileCapability(fd)
    }

    /// Extracts a socket descriptor from the message, transferring ownership to the caller.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned capability owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: A `SocketCapability` if the descriptor exists and is a socket, otherwise `nil`
    public mutating func socketDescriptor(at index: Int = 0) -> SocketCapability? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .socket else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return SocketCapability(fd)
    }

    /// Extracts a pipe descriptor from the message, transferring ownership to the caller.
    ///
    /// Note: Since pipes have separate read and write capabilities (`PipeReadCapability`,
    /// `PipeWriteCapability`), but `DescriptorKind.pipe` doesn't distinguish between them,
    /// this method returns the raw file descriptor. The caller must know which end they're
    /// receiving and create the appropriate capability type.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The caller owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: The file descriptor if it exists and is a pipe, otherwise `nil`
    public mutating func pipeDescriptor(at index: Int = 0) -> Int32? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .pipe else { return nil }
        return descriptors[index].take()
    }

    /// Extracts a process descriptor from the message, transferring ownership to the caller.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned capability owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: A `ProcessCapability` if the descriptor exists and is a process descriptor, otherwise `nil`
    public mutating func processDescriptor(at index: Int = 0) -> ProcessCapability? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .process else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return ProcessCapability(fd)
    }

    /// Extracts a kqueue descriptor from the message, transferring ownership to the caller.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned capability owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: A `KqueueCapability` if the descriptor exists and is a kqueue, otherwise `nil`
    public mutating func kqueueDescriptor(at index: Int = 0) -> KqueueCapability? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .kqueue else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return KqueueCapability(fd)
    }

    /// Extracts a shared memory descriptor from the message, transferring ownership to the caller.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned capability owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: A `SharedMemoryCapability` if the descriptor exists and is shared memory, otherwise `nil`
    public mutating func sharedMemoryDescriptor(at index: Int = 0) -> SharedMemoryCapability? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .shm else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return SharedMemoryCapability(fd)
    }

    /// Extracts an event descriptor from the message, transferring ownership to the caller.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned capability owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: An `EventCapability` if the descriptor exists and is an event descriptor, otherwise `nil`
    public mutating func eventDescriptor(at index: Int = 0) -> EventCapability? {
        guard index < descriptors.count else { return nil }
        guard descriptors[index].kind == .event else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return EventCapability(fd)
    }

    /// Extracts a jail descriptor from the message, transferring ownership to the caller.
    ///
    /// Since jail descriptors carry an additional "owning" flag, this method returns a
    /// `JailDescriptorInfo` containing both the descriptor and the ownership status.
    ///
    /// After calling this method, the descriptor is removed from the message and will not
    /// be closed when the message is destroyed. The returned descriptor owns the file descriptor.
    ///
    /// - Parameter index: The index of the descriptor (default: 0)
    /// - Returns: A `JailDescriptorInfo` if the descriptor exists and is a jail descriptor, otherwise `nil`
    public mutating func jailDescriptor(at index: Int = 0) -> JailDescriptorInfo? {
        guard index < descriptors.count else { return nil }
        guard case .jail(let owning) = descriptors[index].kind else { return nil }
        guard let fd = descriptors[index].take() else { return nil }
        return JailDescriptorInfo(descriptor: SystemJailDescriptor(fd), owning: owning)
    }
}

// MARK: - MessageID

/// Identifies the kind of message exchanged over a BPC connection.
///
/// ## FPCMessage ID Space Allocation
///
/// The 32-bit message ID space is divided into reserved and user ranges:
///
/// - **0x00000000 - 0x000000FF (0-255)**: Reserved for system/protocol messages
/// - **0x00000100 - 0xFFFFFFFF (256+)**: Available for application-specific messages
///
/// ## Usage
///
/// Use the predefined constants for standard BPC messages, or create your own in the user range:
///
/// ```swift
/// extension MessageID {
///     // User message IDs start at 256
///     static let fileOpen = MessageID(rawValue: 256)
///     static let fileOpenReply = MessageID(rawValue: 257)
///     static let fileRead = MessageID(rawValue: 258)
///     static let fileReadReply = MessageID(rawValue: 259)
/// }
///
/// let message = FPCMessage(id: .fileOpen, payload: data)
/// ```
public struct MessageID: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // MARK: - ID Space Boundaries

    /// The upper bound (exclusive) of the system-reserved message ID range.
    ///
    /// User-defined message IDs should be >= this value.
    public static let userSpaceStart: UInt32 = 256

    /// Checks if this message ID is in the system-reserved range (0-255).
    public var isSystemReserved: Bool {
        rawValue < Self.userSpaceStart
    }

    /// Checks if this message ID is in the user-defined range (256+).
    public var isUserDefined: Bool {
        rawValue >= Self.userSpaceStart
    }

    // MARK: - Standard System FPCMessage Types

    /// Liveness probe sent by the client.
    public static let ping = MessageID(rawValue: 1)

    /// Response to a ``ping``.
    public static let pong = MessageID(rawValue: 2)

    /// Requests a name lookup from the server.
    public static let lookup = MessageID(rawValue: 3)

    /// Server reply to a ``lookup``.
    public static let lookupReply = MessageID(rawValue: 4)

    /// Requests a subscription to server-side events.
    public static let subscribe = MessageID(rawValue: 5)

    /// Server acknowledgement of a ``subscribe``.
    public static let subscribeAck = MessageID(rawValue: 6)

    /// An unsolicited event pushed by the server.
    public static let event = MessageID(rawValue: 7)

    /// Indicates an error condition.
    public static let error = MessageID(rawValue: 255)
}

extension MessageID: CustomStringConvertible {
    public var description: String {
        switch rawValue {
        case 1: return "ping"
        case 2: return "pong"
        case 3: return "lookup"
        case 4: return "lookupReply"
        case 5: return "subscribe"
        case 6: return "subscribeAck"
        case 7: return "event"
        case 255: return "error"
        default:
            if isSystemReserved {
                return "reserved(\(rawValue))"
            } else {
                return "user(\(rawValue))"
            }
        }
    }
}
