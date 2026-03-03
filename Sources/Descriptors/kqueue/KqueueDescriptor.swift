/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc
import Foundation
import FreeBSDKit

// MARK: - Kqueue Descriptor

/// A BSD descriptor representing a `kqueue(2)`.
public protocol KqueueDescriptor: Descriptor, ~Copyable {

    /// Create a new kqueue descriptor.
    static func makeKqueue() throws -> Self

    /// Perform a kevent operation.
    ///
    /// - Parameters:
    ///   - changes: Events to register.
    ///   - maxEvents: Maximum number of events to return.
    ///   - timeout: Optional timeout; `nil` waits indefinitely.
    ///
    /// - Returns: (number of events, returned events)
    func kevent(
        changes: [kevent],
        maxEvents: Int,
        timeout: TimeInterval?
    ) throws -> (Int, [kevent])
}

// MARK: - C ABI hook
@_silgen_name("kevent")
public func _kevent_c(
    _ kq: Int32,
    _ changelist: UnsafePointer<kevent>?,
    _ nchanges: Int32,
    _ eventlist: UnsafeMutablePointer<kevent>?,
    _ nevents: Int32,
    _ timeout: UnsafePointer<timespec>?
) -> Int32

// MARK: - Default Implementations

public extension KqueueDescriptor where Self: ~Copyable {

    static func makeKqueue() throws -> Self {
        let raw = Glibc.kqueue()
        guard raw >= 0 else {
            try BSDError.throwErrno(errno)
        }
        return Self(raw)
    }

   func kevent(
        changes: [kevent],
        maxEvents: Int,
        timeout: TimeInterval?
    ) throws -> (Int, [kevent]) {
        guard maxEvents >= 0 else {
            throw POSIXError(.EINVAL)
        }
        if let t = timeout {
            guard t >= 0 else {
                throw POSIXError(.EINVAL)
            }
        }

        var tsStorage: timespec?
        if let timeout = timeout {
            let sec = Int(timeout)
            let frac = timeout - Double(sec)
            let nsec = min(max(Int(frac * 1_000_000_000), 0), 999_999_999)
            tsStorage = timespec(tv_sec: time_t(sec), tv_nsec: nsec)
        }

        // Only allocate if we’re actually returning events.
        var events: [kevent] = maxEvents > 0
            ? Array(repeating: Glibc.kevent(), count: maxEvents)
            : []

        let count: Int = try self.unsafe { fd in
            let result: Int32 = events.withUnsafeMutableBufferPointer { evBuf in
                changes.withUnsafeBufferPointer { chBuf in
                    let changelistPtr: UnsafePointer<kevent>? =
                        (chBuf.count > 0) ? chBuf.baseAddress : nil
                    let eventlistPtr: UnsafeMutablePointer<kevent>? =
                        (evBuf.count > 0) ? evBuf.baseAddress : nil

                    if var ts = tsStorage {
                        return _kevent_c(
                            fd,
                            changelistPtr,
                            Int32(chBuf.count),
                            eventlistPtr,
                            Int32(evBuf.count),
                            &ts
                        )
                    } else {
                        return _kevent_c(
                            fd,
                            changelistPtr,
                            Int32(chBuf.count),
                            eventlistPtr,
                            Int32(evBuf.count),
                            nil
                        )
                    }
                }
            }

            guard result >= 0 else { try BSDError.throwErrno(errno) }
            return Int(result)
        }

        return (count, Array(events.prefix(count)))
    }
}
