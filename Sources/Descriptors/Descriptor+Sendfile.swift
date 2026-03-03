/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc
import Foundation
import FreeBSDKit

// MARK: - OpaqueDescriptorRef + Sendfile

public extension OpaqueDescriptorRef {

    /// Send a file to a socket using zero-copy transfer.
    ///
    /// `sendfile(2)` transmits file data directly from the kernel's buffer cache
    /// to the socket without copying through user space.
    ///
    /// - Parameters:
    ///   - socket: Socket descriptor to send to
    ///   - offset: Starting offset in the file (0 for beginning)
    ///   - count: Number of bytes to send (nil for entire file from offset)
    ///   - flags: Sendfile behavior flags
    /// - Returns: Result containing bytes sent and completion status
    /// - Throws: `BSDError` on failure, `POSIXError(.EBADF)` if descriptor is invalid
    func sendTo(
        _ socket: OpaqueDescriptorRef,
        offset: off_t = 0,
        count: Int? = nil,
        flags: SendfileFlags = []
    ) throws -> SendfileResult {
        guard let fileFD = self.toBSDValue() else {
            throw POSIXError(.EBADF)
        }
        guard let socketFD = socket.toBSDValue() else {
            throw POSIXError(.EBADF)
        }
        return try sendfile(from: fileFD, to: socketFD, offset: offset, count: count, flags: flags)
    }

    /// Send a file to a socket with headers and/or trailers.
    ///
    /// - Parameters:
    ///   - socket: Socket descriptor to send to
    ///   - offset: Starting offset in the file (0 for beginning)
    ///   - count: Number of bytes to send (nil for entire file from offset)
    ///   - headersTrailers: Headers and trailers to send with the file
    ///   - flags: Sendfile behavior flags
    /// - Returns: Result containing bytes sent and completion status
    /// - Throws: `BSDError` on failure, `POSIXError(.EBADF)` if descriptor is invalid
    func sendTo(
        _ socket: OpaqueDescriptorRef,
        offset: off_t = 0,
        count: Int? = nil,
        headersTrailers: borrowing SendfileHeadersTrailers,
        flags: SendfileFlags = []
    ) throws -> SendfileResult {
        guard let fileFD = self.toBSDValue() else {
            throw POSIXError(.EBADF)
        }
        guard let socketFD = socket.toBSDValue() else {
            throw POSIXError(.EBADF)
        }
        return try sendfile(
            from: fileFD,
            to: socketFD,
            offset: offset,
            count: count,
            headersTrailers: headersTrailers,
            flags: flags
        )
    }
}

// MARK: - FileDescriptor + Sendfile

public extension FileDescriptor where Self: ~Copyable {

    /// Send this file's contents to a socket using zero-copy transfer.
    ///
    /// `sendfile(2)` transmits file data directly from the kernel's buffer cache
    /// to the socket without copying through user space. This is significantly
    /// more efficient than read()/write() loops for serving static files.
    ///
    /// - Parameters:
    ///   - socket: Stream socket to send to
    ///   - offset: Starting offset in the file (0 for beginning)
    ///   - count: Number of bytes to send (nil for entire file from offset)
    ///   - flags: Sendfile behavior flags
    /// - Returns: Result containing bytes sent and completion status
    /// - Throws: `BSDError` on failure
    func sendTo(
        _ socket: borrowing some SocketDescriptor & ~Copyable,
        offset: off_t = 0,
        count: Int? = nil,
        flags: SendfileFlags = []
    ) throws -> SendfileResult {
        try self.unsafe { fileFD in
            try socket.unsafe { socketFD in
                try sendfile(from: fileFD, to: socketFD, offset: offset, count: count, flags: flags)
            }
        }
    }

    /// Send this file's contents to a socket with headers and/or trailers.
    ///
    /// This variant allows prepending headers (e.g., HTTP response headers)
    /// and appending trailers (e.g., chunked encoding terminator) to the file
    /// data, all sent in a single efficient operation.
    ///
    /// - Parameters:
    ///   - socket: Stream socket to send to
    ///   - offset: Starting offset in the file (0 for beginning)
    ///   - count: Number of bytes to send (nil for entire file from offset)
    ///   - headersTrailers: Headers and trailers to send with the file
    ///   - flags: Sendfile behavior flags
    /// - Returns: Result containing bytes sent and completion status
    /// - Throws: `BSDError` on failure
    func sendTo(
        _ socket: borrowing some SocketDescriptor & ~Copyable,
        offset: off_t = 0,
        count: Int? = nil,
        headersTrailers: borrowing SendfileHeadersTrailers,
        flags: SendfileFlags = []
    ) throws -> SendfileResult {
        try self.unsafe { fileFD in
            try socket.unsafe { socketFD in
                try sendfile(
                    from: fileFD,
                    to: socketFD,
                    offset: offset,
                    count: count,
                    headersTrailers: headersTrailers,
                    flags: flags
                )
            }
        }
    }
}

// MARK: - SocketDescriptor + Sendfile

public extension SocketDescriptor where Self: ~Copyable {

    /// Receive a file from another descriptor using zero-copy transfer.
    ///
    /// This is a convenience method that calls sendfile with this socket
    /// as the destination.
    ///
    /// - Parameters:
    ///   - file: File descriptor to send from
    ///   - offset: Starting offset in the file (0 for beginning)
    ///   - count: Number of bytes to send (nil for entire file from offset)
    ///   - flags: Sendfile behavior flags
    /// - Returns: Result containing bytes sent and completion status
    /// - Throws: `BSDError` on failure
    func receiveFile(
        from file: borrowing some FileDescriptor & ~Copyable,
        offset: off_t = 0,
        count: Int? = nil,
        flags: SendfileFlags = []
    ) throws -> SendfileResult {
        try file.unsafe { fileFD in
            try self.unsafe { socketFD in
                try sendfile(from: fileFD, to: socketFD, offset: offset, count: count, flags: flags)
            }
        }
    }
}
