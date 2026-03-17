/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc
import Foundation
import FreeBSDKit

/// A pair of connected sockets created via socketpair(2).
///
/// This struct wraps two connected sockets of the same type. Since sockets may
/// be noncopyable, this wrapper provides a way to return paired sockets from
/// factory methods. Marked as `@frozen` to allow partial consumption across
/// module boundaries.
@frozen
public struct SocketPair<Socket: ~Copyable>: ~Copyable {
    public var first: Socket
    public var second: Socket

    public init(first: consuming Socket, second: consuming Socket) {
        self.first = first
        self.second = second
    }
}

/// Socket descriptor protocol providing network communication capabilities
public protocol SocketDescriptor: StreamDescriptor, ~Copyable {
    static func socket(domain: SocketDomain, type: SocketType, protocol: SocketProtocol) throws -> Self
    func bind(address: SocketAddress) throws
    func bind<D: DirectoryDescriptor>(at directory: borrowing D, address: SocketAddress) throws where D: ~Copyable
    func listen(backlog: Int32) throws
    func accept() throws -> Self
    func connect(address: SocketAddress) throws
    func connect<D: DirectoryDescriptor>(at directory: borrowing D, address: SocketAddress) throws where D: ~Copyable
    func shutdown(how: SocketShutdown) throws
    func sendDescriptors(_ descriptors: [OpaqueDescriptorRef], payload: Data) throws
    func recvDescriptors(maxDescriptors: Int, bufferSize: Int) throws -> (Data, [OpaqueDescriptorRef])
}

// MARK: - Default implementations

public extension SocketDescriptor where Self: ~Copyable {

    /// Creates a pair of connected sockets using socketpair(2).
    ///
    /// - Parameters:
    ///   - domain: The socket domain (typically `.unix` for local IPC).
    ///   - type: The socket type (e.g., `.stream`, `.datagram`).
    ///   - protocol: The protocol to use (defaults to `.default`).
    /// - Returns: A `SocketPair` containing two connected sockets.
    /// - Throws: A BSD error if the socketpair call fails.
    static func socketPair(
        domain: SocketDomain,
        type: SocketType,
        protocol: SocketProtocol = .default
    ) throws -> SocketPair<Self> {
        var fds = [Int32](repeating: -1, count: 2)
        guard Glibc.socketpair(domain.rawValue, type.rawValue, `protocol`.rawValue, &fds) == 0 else {
            try BSDError.throwErrno(errno)
        }
        return SocketPair(first: Self(fds[0]), second: Self(fds[1]))
    }

    func listen(backlog: Int32 = 128) throws {
        try self.unsafe { fd in
            guard Glibc.listen(fd, backlog) == 0 else {
                try BSDError.throwErrno(errno)
            }
        }
    }

    func shutdown(how: SocketShutdown) throws {
        try self.unsafe { fd in
            guard Glibc.shutdown(fd, how.rawValue) == 0 else {
                try BSDError.throwErrno(errno)
            }
        }
    }

    static func socket(domain: SocketDomain, type: SocketType, protocol: SocketProtocol) throws -> Self {
        let rawFD = Glibc.socket(domain.rawValue, type.rawValue, `protocol`.rawValue)
        guard rawFD >= 0 else {
            try BSDError.throwErrno(errno)
        }
        return Self(rawFD)
    }

    func bind(address: SocketAddress) throws {
        try self.unsafe { fd in
            try address.withSockAddr { addr, len in
                guard Glibc.bind(fd, addr, len) == 0 else {
                    try BSDError.throwErrno(errno)
                }
            }
        }
    }

    /// Binds the socket to an address relative to a directory descriptor.
    ///
    /// This is the `bindat(2)` syscall, which allows binding to a Unix domain
    /// socket path relative to a directory file descriptor. This is useful in
    /// Capsicum sandboxes where you have a capability for the directory but
    /// cannot use absolute paths.
    ///
    /// - Parameters:
    ///   - directory: A directory descriptor to use as the base for the path.
    ///   - address: The socket address (should be a Unix domain socket address
    ///     with a relative path).
    /// - Throws: A BSD error if the bind fails.
    func bind<D: DirectoryDescriptor>(at directory: borrowing D, address: SocketAddress) throws where D: ~Copyable {
        try self.unsafe { sockFD in
            try directory.unsafe { dirFD in
                try address.withSockAddr { addr, len in
                    guard Glibc.bindat(dirFD, sockFD, addr, len) == 0 else {
                        try BSDError.throwErrno(errno)
                    }
                }
            }
        }
    }

    func accept() throws -> Self {
        return try self.unsafe { fd in
            let newFD = Glibc.accept(fd, nil, nil)
            guard newFD >= 0 else {
                try BSDError.throwErrno(errno)
            }
            return Self(newFD)
        }
    }

    func connect(address: SocketAddress) throws {
        try self.unsafe { fd in
            try address.withSockAddr { addr, len in
                guard Glibc.connect(fd, addr, len) == 0 else {
                    try BSDError.throwErrno(errno)
                }
            }
        }
    }

    /// Connects the socket to an address relative to a directory descriptor.
    ///
    /// This is the `connectat(2)` syscall, which allows connecting to a Unix
    /// domain socket path relative to a directory file descriptor. This is useful
    /// in Capsicum sandboxes where you have a capability for the directory but
    /// cannot use absolute paths.
    ///
    /// - Parameters:
    ///   - directory: A directory descriptor to use as the base for the path.
    ///   - address: The socket address (should be a Unix domain socket address
    ///     with a relative path).
    /// - Throws: A BSD error if the connect fails.
    func connect<D: DirectoryDescriptor>(at directory: borrowing D, address: SocketAddress) throws where D: ~Copyable {
        try self.unsafe { sockFD in
            try directory.unsafe { dirFD in
                try address.withSockAddr { addr, len in
                    guard Glibc.connectat(dirFD, sockFD, addr, len) == 0 else {
                        try BSDError.throwErrno(errno)
                    }
                }
            }
        }
    }
}

// MARK: - CMSG Helpers (Swift replacements for macros)

@inline(__always)
private func _CMSG_ALIGN(_ len: Int) -> Int {
    // CMSG_ALIGN uses alignment of size_t, not cmsghdr struct alignment
    let a = MemoryLayout<size_t>.size
    return (len + a - 1) & ~(a - 1)
}

@inline(__always)
private func CMSG_LEN(_ dataLen: Int) -> Int {
    _CMSG_ALIGN(MemoryLayout<cmsghdr>.size) + dataLen
}

@inline(__always)
private func CMSG_SPACE(_ dataLen: Int) -> Int {
    _CMSG_ALIGN(MemoryLayout<cmsghdr>.size) + _CMSG_ALIGN(dataLen)
}

@inline(__always)
private func CMSG_FIRSTHDR(_ msg: UnsafePointer<msghdr>) -> UnsafeMutablePointer<cmsghdr>? {
    guard msg.pointee.msg_controllen >= MemoryLayout<cmsghdr>.size else { return nil }
    return msg.pointee.msg_control?.assumingMemoryBound(to: cmsghdr.self)
}

@inline(__always)
private func CMSG_NXTHDR(
    _ msg: UnsafePointer<msghdr>,
    _ cmsg: UnsafePointer<cmsghdr>
) -> UnsafeMutablePointer<cmsghdr>? {
    let next = UnsafeRawPointer(cmsg)
        .advanced(by: _CMSG_ALIGN(Int(cmsg.pointee.cmsg_len)))

    let base = msg.pointee.msg_control!
    let end  = base.advanced(by: Int(msg.pointee.msg_controllen))

    guard next + MemoryLayout<cmsghdr>.size <= end else { return nil }
    return UnsafeMutablePointer(mutating: next.assumingMemoryBound(to: cmsghdr.self))
}

@inline(__always)
private func CMSG_DATA(_ cmsg: UnsafePointer<cmsghdr>) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer(mutating: UnsafeRawPointer(cmsg))
        .advanced(by: _CMSG_ALIGN(MemoryLayout<cmsghdr>.size))
}

public extension SocketDescriptor where Self: ~Copyable {

    func sendDescriptors(
        _ descriptors: [OpaqueDescriptorRef],
        payload: Data
    ) throws {
        try self.unsafe { sockFD in
            var rawFDs: [RawDesc] = []
            rawFDs.reserveCapacity(descriptors.count)

            // Convert all descriptors to FDs, throwing if any conversion fails
            for d in descriptors {
                guard let rawFD = d.toBSDValue() else {
                    throw POSIXError(.EINVAL)
                }
                rawFDs.append(rawFD)
            }

            // Allow empty payload for FD-only messages
            // Use a 1-byte dummy if payload is empty (portable pattern)
            let actualPayload = payload.isEmpty ? Data([0]) : payload

            let controlLen = CMSG_SPACE(rawFDs.count * MemoryLayout<RawDesc>.size)
            var control = [UInt8](repeating: 0, count: controlLen)

            try actualPayload.withUnsafeBytes { payloadPtr in
                var iov = iovec(
                    iov_base: UnsafeMutableRawPointer(mutating: payloadPtr.baseAddress),
                    iov_len: payloadPtr.count
                )

                try control.withUnsafeMutableBytes { ctrlPtr in
                    try withUnsafeMutablePointer(to: &iov) { iovPtr in
                        var msg = msghdr(
                            msg_name: nil,
                            msg_namelen: 0,
                            msg_iov: iovPtr,
                            msg_iovlen: 1,
                            msg_control: ctrlPtr.baseAddress,
                            msg_controllen: socklen_t(ctrlPtr.count),
                            msg_flags: 0
                        )

                        guard let cmsg = CMSG_FIRSTHDR(&msg) else {
                            throw POSIXError(.EINVAL)
                        }

                        cmsg.pointee.cmsg_level = SOL_SOCKET
                        cmsg.pointee.cmsg_type  = SCM_RIGHTS
                        cmsg.pointee.cmsg_len   =
                            socklen_t(CMSG_LEN(rawFDs.count * MemoryLayout<RawDesc>.size))

                        let dataPtr = CMSG_DATA(cmsg).assumingMemoryBound(to: RawDesc.self)
                        for (i, fd) in rawFDs.enumerated() {
                            dataPtr[i] = fd
                        }

                        // MSG_EOR marks end-of-record for SEQPACKET sockets.
                        // This preserves message boundaries on the receiving side.
                        let ret = Glibc.sendmsg(sockFD, &msg, MSG_NOSIGNAL | MSG_EOR)
                        guard ret >= 0 else {
                            try BSDError.throwErrno(errno)
                        }
                    }
                }
            }
        }
    }

        
    func recvDescriptors(
        maxDescriptors: Int = 8,
        bufferSize: Int = 1
    ) throws -> (Data, [OpaqueDescriptorRef]) {

        try self.unsafe { sockFD in
            var buffer  = [UInt8](repeating: 0, count: bufferSize)
            var control = [UInt8](
                repeating: 0,
                count: CMSG_SPACE(maxDescriptors * MemoryLayout<RawDesc>.size)
            )

            return try buffer.withUnsafeMutableBytes { bufPtr in
                try control.withUnsafeMutableBytes { ctrlPtr in

                    var iov = iovec(
                        iov_base: bufPtr.baseAddress,
                        iov_len: bufPtr.count
                    )

                    return try withUnsafeMutablePointer(to: &iov) { iovPtr in
                        var msg = msghdr(
                            msg_name: nil,
                            msg_namelen: 0,
                            msg_iov: iovPtr,
                            msg_iovlen: 1,
                            msg_control: ctrlPtr.baseAddress,
                            msg_controllen: socklen_t(ctrlPtr.count),
                            msg_flags: 0
                        )

                        // Use MSG_CMSG_CLOEXEC to set close-on-exec on received FDs
                        let bytesRead = Glibc.recvmsg(sockFD, &msg, MSG_CMSG_CLOEXEC)
                        guard bytesRead >= 0 else {
                            try BSDError.throwErrno(errno)
                        }

                        // Check for control data truncation
                        if (msg.msg_flags & MSG_CTRUNC) != 0 {
                            throw POSIXError(.EMSGSIZE)
                        }

                        // Check for payload truncation
                        if (msg.msg_flags & MSG_TRUNC) != 0 {
                            throw POSIXError(.EMSGSIZE)
                        }

                        var receivedFDs: [OpaqueDescriptorRef] = []

                        var cmsg = CMSG_FIRSTHDR(&msg)
                        while let hdr = cmsg {
                            if hdr.pointee.cmsg_level == SOL_SOCKET &&
                            hdr.pointee.cmsg_type  == SCM_RIGHTS {

                                let dataLen =
                                    Int(hdr.pointee.cmsg_len) - CMSG_LEN(0)

                                // Validate SCM_RIGHTS payload length
                                guard dataLen >= 0 else {
                                    throw POSIXError(.EINVAL)
                                }

                                guard dataLen % MemoryLayout<RawDesc>.size == 0 else {
                                    throw POSIXError(.EINVAL)
                                }

                                let count = dataLen / MemoryLayout<RawDesc>.size
                                let dataPtr =
                                    CMSG_DATA(hdr).assumingMemoryBound(to: Int32.self)

                                for i in 0..<count {
                                    receivedFDs.append(OpaqueDescriptorRef(dataPtr[i]))
                                }
                            }
                            cmsg = CMSG_NXTHDR(&msg, hdr)
                        }

                        // IMPORTANT: build Data from bufPtr, not `buffer`
                        let data = Data(
                            bytes: bufPtr.baseAddress!,
                            count: bytesRead
                        )

                        return (data, receivedFDs)
                    }
                }
            }
        }
    }
}

// Note: The ~Copyable version above returns SocketPair<Self> for proper ownership.
// For Copyable conformers, the tuple version is also available via the wrapper's
// accessors (first/second).

// MARK: - LOCAL_CREDS_PERSISTENT Support

/// Result from receiving descriptors with credentials.
///
/// This extends the basic `recvDescriptors` result to include optional
/// sender credentials when `LOCAL_CREDS_PERSISTENT` is enabled on the socket.
public struct RecvDescriptorsResult: Sendable {
    /// The received message data.
    public let data: Data

    /// File descriptors received via SCM_RIGHTS.
    public let descriptors: [OpaqueDescriptorRef]

    /// Sender credentials from SCM_CREDS2, if available.
    ///
    /// This is populated when `LOCAL_CREDS_PERSISTENT` has been enabled
    /// on the receiving socket via `enablePersistentCredentials()`.
    public let credentials: SocketCredentials?

    public init(data: Data, descriptors: [OpaqueDescriptorRef], credentials: SocketCredentials? = nil) {
        self.data = data
        self.descriptors = descriptors
        self.credentials = credentials
    }
}

/// Credentials received via SCM_CREDS2 control message.
///
/// This is the socket-level representation of credentials from `sockcred2`.
/// Higher-level protocols (like FPC) may wrap this in their own types.
public struct SocketCredentials: Sendable, Equatable, Hashable {
    /// Real user ID of the sending process.
    public let realUID: uid_t

    /// Effective user ID of the sending process.
    public let effectiveUID: uid_t

    /// Real group ID of the sending process.
    public let realGID: gid_t

    /// Effective group ID of the sending process.
    public let effectiveGID: gid_t

    /// Process ID of the sending process.
    public let pid: pid_t

    /// Supplementary groups of the sending process.
    public let groups: [gid_t]

    public init(
        realUID: uid_t,
        effectiveUID: uid_t,
        realGID: gid_t,
        effectiveGID: gid_t,
        pid: pid_t,
        groups: [gid_t] = []
    ) {
        self.realUID = realUID
        self.effectiveUID = effectiveUID
        self.realGID = realGID
        self.effectiveGID = effectiveGID
        self.pid = pid
        self.groups = groups
    }
}

public extension SocketDescriptor where Self: ~Copyable {

    /// Enables persistent credential delivery via SCM_CREDS2.
    ///
    /// After calling this method, every `recvmsg()` on this socket will include
    /// the sender's credentials in the control message data. Use
    /// `recvDescriptorsWithCredentials()` to receive both descriptors and credentials.
    ///
    /// This uses the `LOCAL_CREDS_PERSISTENT` socket option, which provides:
    /// - Real and effective UID/GID (not just effective like `LOCAL_PEERCRED`)
    /// - Process ID
    /// - Supplementary groups
    /// - Per-message credentials (not just at connection time)
    ///
    /// - Throws: A BSD error if the socket option cannot be set.
    func enablePersistentCredentials() throws {
        try self.unsafe { fd in
            var one: Int32 = 1
            guard setsockopt(fd, SOL_LOCAL, LOCAL_CREDS_PERSISTENT, &one, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                try BSDError.throwErrno(errno)
            }
        }
    }

    /// Receives data, file descriptors, and optionally sender credentials.
    ///
    /// This is an extended version of `recvDescriptors` that also parses
    /// `SCM_CREDS2` control messages when `LOCAL_CREDS_PERSISTENT` is enabled.
    ///
    /// - Parameters:
    ///   - maxDescriptors: Maximum number of file descriptors to receive.
    ///   - bufferSize: Size of the data buffer.
    /// - Returns: A `RecvDescriptorsResult` containing data, descriptors, and optional credentials.
    /// - Throws: A BSD error if receiving fails.
    func recvDescriptorsWithCredentials(
        maxDescriptors: Int = 8,
        bufferSize: Int = 1
    ) throws -> RecvDescriptorsResult {
        try self.unsafe { sockFD in
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            // Calculate control buffer size to accommodate both SCM_RIGHTS and SCM_CREDS2
            // SCM_CREDS2 uses sockcred2 which has a variable-length groups array
            let rightsSpace = CMSG_SPACE(maxDescriptors * MemoryLayout<RawDesc>.size)
            let credsSpace = CMSG_SPACE(MemoryLayout<sockcred2>.size + Int(NGROUPS_MAX) * MemoryLayout<gid_t>.size)
            let controlLen = rightsSpace + credsSpace

            var control = [UInt8](repeating: 0, count: controlLen)

            return try buffer.withUnsafeMutableBytes { bufPtr in
                try control.withUnsafeMutableBytes { ctrlPtr in
                    var iov = iovec(
                        iov_base: bufPtr.baseAddress,
                        iov_len: bufPtr.count
                    )

                    return try withUnsafeMutablePointer(to: &iov) { iovPtr in
                        var msg = msghdr(
                            msg_name: nil,
                            msg_namelen: 0,
                            msg_iov: iovPtr,
                            msg_iovlen: 1,
                            msg_control: ctrlPtr.baseAddress,
                            msg_controllen: socklen_t(ctrlPtr.count),
                            msg_flags: 0
                        )

                        // Use MSG_CMSG_CLOEXEC to set close-on-exec on received FDs
                        let bytesRead = Glibc.recvmsg(sockFD, &msg, MSG_CMSG_CLOEXEC)
                        guard bytesRead >= 0 else {
                            try BSDError.throwErrno(errno)
                        }

                        // Check for control data truncation
                        if (msg.msg_flags & MSG_CTRUNC) != 0 {
                            throw POSIXError(.EMSGSIZE)
                        }

                        // Check for payload truncation
                        if (msg.msg_flags & MSG_TRUNC) != 0 {
                            throw POSIXError(.EMSGSIZE)
                        }

                        var receivedFDs: [OpaqueDescriptorRef] = []
                        var credentials: SocketCredentials? = nil

                        var cmsg = CMSG_FIRSTHDR(&msg)
                        while let hdr = cmsg {
                            if hdr.pointee.cmsg_level == SOL_SOCKET &&
                               hdr.pointee.cmsg_type == SCM_RIGHTS {
                                // Parse file descriptors
                                let dataLen = Int(hdr.pointee.cmsg_len) - CMSG_LEN(0)

                                guard dataLen >= 0 else {
                                    throw POSIXError(.EINVAL)
                                }

                                guard dataLen % MemoryLayout<RawDesc>.size == 0 else {
                                    throw POSIXError(.EINVAL)
                                }

                                let count = dataLen / MemoryLayout<RawDesc>.size
                                let dataPtr = CMSG_DATA(hdr).assumingMemoryBound(to: Int32.self)

                                for i in 0..<count {
                                    receivedFDs.append(OpaqueDescriptorRef(dataPtr[i]))
                                }
                            } else if hdr.pointee.cmsg_level == SOL_SOCKET &&
                                      hdr.pointee.cmsg_type == SCM_CREDS2 {
                                // Parse credentials
                                let dataLen = Int(hdr.pointee.cmsg_len) - CMSG_LEN(0)

                                guard dataLen >= MemoryLayout<sockcred2>.size else {
                                    // Invalid credentials, skip but don't fail
                                    cmsg = CMSG_NXTHDR(&msg, hdr)
                                    continue
                                }

                                let credsPtr = CMSG_DATA(hdr).assumingMemoryBound(to: sockcred2.self)
                                let sc = credsPtr.pointee

                                // Extract supplementary groups
                                var groupList: [gid_t] = []
                                let ngroups = Int(sc.sc_ngroups)
                                if ngroups > 0 {
                                    withUnsafePointer(to: credsPtr.pointee.sc_groups) { groupsPtr in
                                        let gidsPtr = UnsafeRawPointer(groupsPtr).assumingMemoryBound(to: gid_t.self)
                                        for i in 0..<min(ngroups, Int(NGROUPS_MAX)) {
                                            groupList.append(gidsPtr[i])
                                        }
                                    }
                                }

                                credentials = SocketCredentials(
                                    realUID: sc.sc_uid,
                                    effectiveUID: sc.sc_euid,
                                    realGID: sc.sc_gid,
                                    effectiveGID: sc.sc_egid,
                                    pid: sc.sc_pid,
                                    groups: groupList
                                )
                            }

                            cmsg = CMSG_NXTHDR(&msg, hdr)
                        }

                        let data = Data(bytes: bufPtr.baseAddress!, count: bytesRead)

                        return RecvDescriptorsResult(
                            data: data,
                            descriptors: receivedFDs,
                            credentials: credentials
                        )
                    }
                }
            }
        }
    }
}