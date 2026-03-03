/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

@preconcurrency import Glibc
import FreeBSDKit
import Jails

/// A parsed kqueue event result.
///
/// `KEventResult` provides a type-safe way to interpret events returned
/// from `kevent()`. Each case corresponds to a filter type and contains
/// the relevant data for that filter.
public enum KEventResult: @unchecked Sendable {
    /// A descriptor is ready for reading.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor
    ///   - bytesAvailable: Number of bytes available to read
    ///   - eof: True if EOF condition detected
    ///   - udata: User data pointer
    case readable(fd: Int32, bytesAvailable: Int, eof: Bool, udata: UnsafeMutableRawPointer?)

    /// A descriptor is ready for writing.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor
    ///   - bufferSpace: Bytes of space available in write buffer
    ///   - eof: True if reader disconnected
    ///   - udata: User data pointer
    case writable(fd: Int32, bufferSpace: Int, eof: Bool, udata: UnsafeMutableRawPointer?)

    /// A descriptor's write buffer is empty.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor
    ///   - udata: User data pointer
    case empty(fd: Int32, udata: UnsafeMutableRawPointer?)

    /// A vnode event occurred.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor
    ///   - events: The events that occurred
    ///   - udata: User data pointer
    case vnode(fd: Int32, events: VNodeEvents, udata: UnsafeMutableRawPointer?)

    /// A process event occurred.
    ///
    /// - Parameters:
    ///   - pid: The process ID
    ///   - events: The events that occurred
    ///   - exitStatus: Exit status if `events` contains `.exit`
    ///   - udata: User data pointer
    case process(pid: pid_t, events: ProcessEvents, exitStatus: Int32?, udata: UnsafeMutableRawPointer?)

    /// A process descriptor event occurred.
    ///
    /// - Parameters:
    ///   - fd: The process descriptor
    ///   - events: The events that occurred
    ///   - exitStatus: Exit status if `events` contains `.exit`
    ///   - udata: User data pointer
    case processDesc(fd: Int32, events: ProcessEvents, exitStatus: Int32?, udata: UnsafeMutableRawPointer?)

    /// A signal was delivered.
    ///
    /// - Parameters:
    ///   - signal: The signal that was delivered
    ///   - count: Number of times the signal was delivered since last check
    ///   - udata: User data pointer
    case signal(BSDSignal, count: Int, udata: UnsafeMutableRawPointer?)

    /// A timer expired.
    ///
    /// - Parameters:
    ///   - id: The timer identifier
    ///   - expirations: Number of times the timer expired since last check
    ///   - udata: User data pointer
    case timer(id: UInt, expirations: Int, udata: UnsafeMutableRawPointer?)

    /// A user event was triggered.
    ///
    /// - Parameters:
    ///   - id: The event identifier
    ///   - fflags: The user-defined flags (lower 24 bits)
    ///   - udata: User data pointer
    case user(id: UInt, fflags: UInt32, udata: UnsafeMutableRawPointer?)

    /// A jail event occurred.
    ///
    /// - Parameters:
    ///   - jid: The jail ID
    ///   - events: The events that occurred
    ///   - data: Event-specific data (PID for attach, child JID for child)
    ///   - udata: User data pointer
    case jail(jid: Int32, events: JailEvents, data: Int, udata: UnsafeMutableRawPointer?)

    /// A jail descriptor event occurred.
    ///
    /// - Parameters:
    ///   - fd: The jail descriptor
    ///   - events: The events that occurred
    ///   - data: Event-specific data (PID for attach, child JID for child)
    ///   - udata: User data pointer
    case jailDesc(fd: Int32, events: JailEvents, data: Int, udata: UnsafeMutableRawPointer?)

    /// An error occurred processing an event.
    ///
    /// - Parameters:
    ///   - ident: The event identifier
    ///   - filter: The filter type
    ///   - errno: The error code
    ///   - udata: User data pointer
    case error(ident: UInt, filter: Int16, errno: Int32, udata: UnsafeMutableRawPointer?)

    /// An unknown filter type was received.
    ///
    /// - Parameter raw: The raw kevent structure
    case unknown(raw: kevent)

    // MARK: - Parsing

    /// Parse a raw kevent into a typed result.
    ///
    /// - Parameter ev: The raw kevent structure
    /// - Returns: A typed `KEventResult`
    public init(from ev: kevent) {
        let flags = KEventFlags(rawValue: ev.flags)

        // Check for error first
        if flags.contains(.error) && ev.data != 0 {
            self = .error(
                ident: ev.ident,
                filter: ev.filter,
                errno: Int32(ev.data),
                udata: ev.udata
            )
            return
        }

        switch ev.filter {
        case Int16(EVFILT_READ):
            self = .readable(
                fd: Int32(ev.ident),
                bytesAvailable: ev.data,
                eof: flags.contains(.eof),
                udata: ev.udata
            )

        case Int16(EVFILT_WRITE):
            self = .writable(
                fd: Int32(ev.ident),
                bufferSpace: ev.data,
                eof: flags.contains(.eof),
                udata: ev.udata
            )

        case Int16(EVFILT_EMPTY):
            self = .empty(fd: Int32(ev.ident), udata: ev.udata)

        case Int16(EVFILT_VNODE):
            self = .vnode(
                fd: Int32(ev.ident),
                events: VNodeEvents(rawValue: ev.fflags),
                udata: ev.udata
            )

        case Int16(EVFILT_PROC):
            let events = ProcessEvents(rawValue: ev.fflags)
            let exitStatus: Int32? = events.contains(.exit) ? Int32(ev.data) : nil
            self = .process(
                pid: pid_t(ev.ident),
                events: events,
                exitStatus: exitStatus,
                udata: ev.udata
            )

        case Int16(EVFILT_PROCDESC):
            let events = ProcessEvents(rawValue: ev.fflags)
            let exitStatus: Int32? = events.contains(.exit) ? Int32(ev.data) : nil
            self = .processDesc(
                fd: Int32(ev.ident),
                events: events,
                exitStatus: exitStatus,
                udata: ev.udata
            )

        case Int16(EVFILT_SIGNAL):
            let sig = BSDSignal(rawValue: Int32(ev.ident))
            if let sig = sig {
                self = .signal(sig, count: ev.data, udata: ev.udata)
            } else {
                self = .unknown(raw: ev)
            }

        case Int16(EVFILT_TIMER):
            self = .timer(id: ev.ident, expirations: ev.data, udata: ev.udata)

        case Int16(EVFILT_USER):
            // User flags are in lower 24 bits of fflags
            let userFlags = ev.fflags & UInt32(NOTE_FFLAGSMASK)
            self = .user(id: ev.ident, fflags: userFlags, udata: ev.udata)

        case Int16(EVFILT_JAIL):
            self = .jail(
                jid: Int32(bitPattern: UInt32(truncatingIfNeeded: ev.ident)),
                events: JailEvents(rawValue: ev.fflags),
                data: ev.data,
                udata: ev.udata
            )

        case Int16(EVFILT_JAILDESC):
            self = .jailDesc(
                fd: Int32(ev.ident),
                events: JailEvents(rawValue: ev.fflags),
                data: ev.data,
                udata: ev.udata
            )

        default:
            self = .unknown(raw: ev)
        }
    }

    /// Parse an array of raw kevents into typed results.
    ///
    /// - Parameter events: Array of raw kevent structures
    /// - Returns: Array of typed `KEventResult` values
    public static func parse(_ events: [kevent]) -> [KEventResult] {
        events.map { KEventResult(from: $0) }
    }
}

// MARK: - Convenience Accessors

extension KEventResult {
    /// The user data pointer, if present.
    public var udata: UnsafeMutableRawPointer? {
        switch self {
        case .readable(_, _, _, let udata),
             .writable(_, _, _, let udata),
             .empty(_, let udata),
             .vnode(_, _, let udata),
             .process(_, _, _, let udata),
             .processDesc(_, _, _, let udata),
             .signal(_, _, let udata),
             .timer(_, _, let udata),
             .user(_, _, let udata),
             .jail(_, _, _, let udata),
             .jailDesc(_, _, _, let udata),
             .error(_, _, _, let udata):
            return udata
        case .unknown:
            return nil
        }
    }

    /// True if this is an error result.
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    /// True if this is an EOF condition.
    public var isEOF: Bool {
        switch self {
        case .readable(_, _, let eof, _),
             .writable(_, _, let eof, _):
            return eof
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension KEventResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .readable(let fd, let bytes, let eof, _):
            return "readable(fd: \(fd), bytes: \(bytes), eof: \(eof))"
        case .writable(let fd, let space, let eof, _):
            return "writable(fd: \(fd), space: \(space), eof: \(eof))"
        case .empty(let fd, _):
            return "empty(fd: \(fd))"
        case .vnode(let fd, let events, _):
            return "vnode(fd: \(fd), events: \(events))"
        case .process(let pid, let events, let status, _):
            if let status = status {
                return "process(pid: \(pid), events: \(events), exitStatus: \(status))"
            }
            return "process(pid: \(pid), events: \(events))"
        case .processDesc(let fd, let events, let status, _):
            if let status = status {
                return "processDesc(fd: \(fd), events: \(events), exitStatus: \(status))"
            }
            return "processDesc(fd: \(fd), events: \(events))"
        case .signal(let sig, let count, _):
            return "signal(\(sig), count: \(count))"
        case .timer(let id, let exp, _):
            return "timer(id: \(id), expirations: \(exp))"
        case .user(let id, let flags, _):
            return "user(id: \(id), fflags: 0x\(String(flags, radix: 16)))"
        case .jail(let jid, let events, let data, _):
            return "jail(jid: \(jid), events: \(events), data: \(data))"
        case .jailDesc(let fd, let events, let data, _):
            return "jailDesc(fd: \(fd), events: \(events), data: \(data))"
        case .error(let ident, let filter, let errno, _):
            return "error(ident: \(ident), filter: \(filter), errno: \(errno))"
        case .unknown(let raw):
            return "unknown(filter: \(raw.filter), ident: \(raw.ident))"
        }
    }
}
