/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc
import Foundation

// MARK: - Sendfile Flags

/// Flags controlling sendfile(2) behavior.
public struct SendfileFlags: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    /// Don't block on disk I/O; return EBUSY if pages aren't in cache.
    ///
    /// Useful for servers that want to avoid blocking on slow storage
    /// and prefer to handle busy pages asynchronously.
    public static let noDiskIO = SendfileFlags(rawValue: SF_NODISKIO)

    /// Wait for data to be sent synchronously.
    ///
    /// Blocks until the data has been transmitted to the peer.
    public static let sync = SendfileFlags(rawValue: SF_SYNC)

    /// Use exact application-specified readahead value.
    ///
    /// By default, the kernel uses heuristics to determine optimal
    /// readahead. Set this flag to override with your specified value.
    public static let userReadahead = SendfileFlags(rawValue: SF_USER_READAHEAD)

    /// Don't cache the sent data in the VM system.
    ///
    /// Data will be freed immediately after being sent. Useful when
    /// sending large files that won't be accessed again soon.
    public static let noCache = SendfileFlags(rawValue: SF_NOCACHE)

    /// Create a flags value with readahead pages specified.
    ///
    /// - Parameters:
    ///   - readahead: Number of pages to read ahead (0-65535)
    ///   - flags: Additional sendfile flags
    /// - Returns: Combined flags value
    public static func withReadahead(_ readahead: UInt16, flags: SendfileFlags = []) -> SendfileFlags {
        SendfileFlags(rawValue: (Int32(readahead) << 16) | flags.rawValue)
    }

    /// The readahead value encoded in these flags.
    public var readahead: UInt16 {
        UInt16(truncatingIfNeeded: rawValue >> 16)
    }
}

// MARK: - Sendfile Headers/Trailers

/// Headers and trailers to send around file data.
///
/// Use this to prepend headers (e.g., HTTP response headers) and append
/// trailers (e.g., chunked encoding terminator) to file data, all in a
/// single zero-copy operation.
public struct SendfileHeadersTrailers: ~Copyable {
    /// Header data to send before the file content.
    public var headers: [Data]

    /// Trailer data to send after the file content.
    public var trailers: [Data]

    /// Create headers/trailers for sendfile.
    ///
    /// - Parameters:
    ///   - headers: Data buffers to send before the file
    ///   - trailers: Data buffers to send after the file
    public init(headers: [Data] = [], trailers: [Data] = []) {
        self.headers = headers
        self.trailers = trailers
    }

    /// Create with a single header.
    public init(header: Data) {
        self.headers = [header]
        self.trailers = []
    }

    /// Create with a single header string.
    public init(header: String) {
        self.headers = [Data(header.utf8)]
        self.trailers = []
    }

    /// Create with header and trailer strings.
    public init(header: String, trailer: String) {
        self.headers = [Data(header.utf8)]
        self.trailers = [Data(trailer.utf8)]
    }
}

// MARK: - Sendfile Result

/// Result of a sendfile operation.
public struct SendfileResult: Sendable {
    /// Total bytes sent, including headers, file data, and trailers.
    public let bytesSent: Int

    /// Whether all requested data was sent.
    ///
    /// If false on a non-blocking socket, call sendfile again to continue.
    public let complete: Bool

    public init(bytesSent: Int, complete: Bool) {
        self.bytesSent = bytesSent
        self.complete = complete
    }
}

// MARK: - Sendfile Functions

/// Send a file to a socket using zero-copy transfer.
///
/// `sendfile(2)` transmits file data directly from the kernel's buffer cache
/// to the socket without copying through user space. This is significantly
/// more efficient than read()/write() loops for serving static files.
///
/// - Parameters:
///   - fileFD: File descriptor of the file to send
///   - socketFD: Stream socket descriptor to send to
///   - offset: Starting offset in the file (0 for beginning)
///   - count: Number of bytes to send (nil for entire file from offset)
///   - flags: Sendfile behavior flags
/// - Returns: Result containing bytes sent and completion status
/// - Throws: `BSDError` on failure
public func sendfile(
    from fileFD: Int32,
    to socketFD: Int32,
    offset: off_t = 0,
    count: Int? = nil,
    flags: SendfileFlags = []
) throws -> SendfileResult {
    var bytesSent: off_t = 0
    let nbytes = count ?? 0  // 0 means send until EOF

    let result = Glibc.sendfile(
        fileFD,
        socketFD,
        offset,
        nbytes,
        nil,
        &bytesSent,
        flags.rawValue
    )

    if result == 0 {
        return SendfileResult(bytesSent: Int(bytesSent), complete: true)
    }

    let err = errno
    if err == EAGAIN || err == EINTR {
        // Partial send on non-blocking socket or interrupted
        return SendfileResult(bytesSent: Int(bytesSent), complete: false)
    }

    throw BSDError.fromErrno(err)
}

/// Send a file to a socket with headers and/or trailers.
///
/// This variant allows prepending headers (e.g., HTTP response headers)
/// and appending trailers (e.g., chunked encoding terminator) to the file
/// data, all sent in a single efficient operation.
///
/// - Parameters:
///   - fileFD: File descriptor of the file to send
///   - socketFD: Stream socket descriptor to send to
///   - offset: Starting offset in the file (0 for beginning)
///   - count: Number of bytes to send (nil for entire file from offset)
///   - headersTrailers: Headers and trailers to send with the file
///   - flags: Sendfile behavior flags
/// - Returns: Result containing bytes sent and completion status
/// - Throws: `BSDError` on failure
public func sendfile(
    from fileFD: Int32,
    to socketFD: Int32,
    offset: off_t = 0,
    count: Int? = nil,
    headersTrailers: borrowing SendfileHeadersTrailers,
    flags: SendfileFlags = []
) throws -> SendfileResult {
    var bytesSent: off_t = 0
    let nbytes = count ?? 0

    // Build iovec arrays for headers and trailers
    // We need to pin the Data buffers during the syscall
    let result: Int32 = headersTrailers.headers.withUnsafeBufferPointers { headerPtrs in
        headersTrailers.trailers.withUnsafeBufferPointers { trailerPtrs in
            // Build header iovecs
            var headerIovecs = headerPtrs.map { ptr in
                iovec(iov_base: UnsafeMutableRawPointer(mutating: ptr.baseAddress), iov_len: ptr.count)
            }

            // Build trailer iovecs
            var trailerIovecs = trailerPtrs.map { ptr in
                iovec(iov_base: UnsafeMutableRawPointer(mutating: ptr.baseAddress), iov_len: ptr.count)
            }

            // Build sf_hdtr
            return headerIovecs.withUnsafeMutableBufferPointer { headerBuf in
                trailerIovecs.withUnsafeMutableBufferPointer { trailerBuf in
                    var hdtr = sf_hdtr(
                        headers: headerBuf.baseAddress,
                        hdr_cnt: Int32(headerBuf.count),
                        trailers: trailerBuf.baseAddress,
                        trl_cnt: Int32(trailerBuf.count)
                    )

                    return Glibc.sendfile(
                        fileFD,
                        socketFD,
                        offset,
                        nbytes,
                        &hdtr,
                        &bytesSent,
                        flags.rawValue
                    )
                }
            }
        }
    }

    if result == 0 {
        return SendfileResult(bytesSent: Int(bytesSent), complete: true)
    }

    let err = errno
    if err == EAGAIN || err == EINTR {
        return SendfileResult(bytesSent: Int(bytesSent), complete: false)
    }

    throw BSDError.fromErrno(err)
}

// MARK: - Array Extension for iovec building

extension Array where Element == Data {
    /// Execute a closure with unsafe buffer pointers to all Data elements.
    func withUnsafeBufferPointers<R>(
        _ body: ([UnsafeBufferPointer<UInt8>]) throws -> R
    ) rethrows -> R {
        var pointers: [UnsafeBufferPointer<UInt8>] = []
        pointers.reserveCapacity(count)

        func recurse(index: Int) throws -> R {
            if index >= count {
                return try body(pointers)
            }
            return try self[index].withUnsafeBytes { buffer in
                pointers.append(buffer.bindMemory(to: UInt8.self))
                return try recurse(index: index + 1)
            }
        }

        return try recurse(index: 0)
    }
}
