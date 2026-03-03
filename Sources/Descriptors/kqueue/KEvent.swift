/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

@preconcurrency import Glibc
import FreeBSDKit
import Jails

// MARK: - KEvent Filter

/// The type of kernel filter for a kqueue event.
public enum KEventFilter: Sendable {
    /// Monitor a descriptor for read readiness.
    ///
    /// - Parameter fd: The file descriptor to monitor
    /// - Parameter lowWaterMark: Optional minimum bytes before triggering (sockets only)
    case read(fd: Int32, lowWaterMark: Int? = nil)

    /// Monitor a descriptor for write readiness.
    ///
    /// - Parameter fd: The file descriptor to monitor
    case write(fd: Int32)

    /// Monitor a descriptor for write buffer empty.
    ///
    /// - Parameter fd: The file descriptor to monitor
    case empty(fd: Int32)

    /// Monitor a file or directory for changes.
    ///
    /// - Parameter fd: The file descriptor to monitor
    /// - Parameter events: The vnode events to watch for
    case vnode(fd: Int32, events: VNodeEvents)

    /// Monitor a process for lifecycle events.
    ///
    /// - Parameter pid: The process ID to monitor
    /// - Parameter events: The process events to watch for
    case proc(pid: pid_t, events: ProcessEvents)

    /// Monitor a process descriptor for lifecycle events.
    ///
    /// - Parameter fd: The process descriptor (from `pdfork()`)
    /// - Parameter events: The process events to watch for
    case procDesc(fd: Int32, events: ProcessEvents)

    /// Monitor for signal delivery.
    ///
    /// - Parameter signal: The signal to monitor
    case signal(BSDSignal)

    /// Create a timer.
    ///
    /// - Parameter id: User-defined identifier for the timer
    /// - Parameter value: The timeout/period value
    /// - Parameter unit: The time unit for `value`
    /// - Parameter absolute: If true, `value` is an absolute time, not a period
    case timer(id: UInt, value: Int64, unit: TimerUnit = .milliseconds, absolute: Bool = false)

    /// A user-defined event.
    ///
    /// - Parameter id: User-defined identifier for the event
    /// - Parameter trigger: If true, trigger the event immediately
    case user(id: UInt, trigger: Bool = false)

    /// Monitor a jail for state changes.
    ///
    /// - Parameter jid: The jail ID to monitor (0 for current jail)
    /// - Parameter events: The jail events to watch for
    case jail(jid: Int32, events: JailEvents)

    /// Monitor a jail descriptor for state changes.
    ///
    /// - Parameter fd: The jail descriptor
    /// - Parameter events: The jail events to watch for
    case jailDesc(fd: Int32, events: JailEvents)

    /// The raw filter value for the C API.
    var rawFilter: Int16 {
        switch self {
        case .read: return Int16(EVFILT_READ)
        case .write: return Int16(EVFILT_WRITE)
        case .empty: return Int16(EVFILT_EMPTY)
        case .vnode: return Int16(EVFILT_VNODE)
        case .proc: return Int16(EVFILT_PROC)
        case .procDesc: return Int16(EVFILT_PROCDESC)
        case .signal: return Int16(EVFILT_SIGNAL)
        case .timer: return Int16(EVFILT_TIMER)
        case .user: return Int16(EVFILT_USER)
        case .jail: return Int16(EVFILT_JAIL)
        case .jailDesc: return Int16(EVFILT_JAILDESC)
        }
    }

    /// The ident value for the C API.
    var ident: UInt {
        switch self {
        case .read(let fd, _): return UInt(fd)
        case .write(let fd): return UInt(fd)
        case .empty(let fd): return UInt(fd)
        case .vnode(let fd, _): return UInt(fd)
        case .proc(let pid, _): return UInt(pid)
        case .procDesc(let fd, _): return UInt(fd)
        case .signal(let sig): return UInt(sig.rawValue)
        case .timer(let id, _, _, _): return id
        case .user(let id, _): return id
        case .jail(let jid, _): return UInt(bitPattern: Int(jid))
        case .jailDesc(let fd, _): return UInt(fd)
        }
    }

    /// The fflags value for the C API.
    var fflags: UInt32 {
        switch self {
        case .read(_, let lowat):
            return lowat != nil ? UInt32(NOTE_LOWAT) : 0
        case .write, .empty:
            return 0
        case .vnode(_, let events):
            return events.rawValue
        case .proc(_, let events), .procDesc(_, let events):
            return events.rawValue
        case .signal:
            return 0
        case .timer(_, _, let unit, let absolute):
            var flags = unit.flags.rawValue
            if absolute {
                flags |= TimerFlags.absoluteTime.rawValue
            }
            return flags
        case .user(_, let trigger):
            return trigger ? UInt32(NOTE_TRIGGER) : 0
        case .jail(_, let events), .jailDesc(_, let events):
            return events.rawValue
        }
    }

    /// The data value for the C API.
    var data: Int {
        switch self {
        case .read(_, let lowat):
            return lowat ?? 0
        case .timer(_, let value, _, _):
            return Int(value)
        default:
            return 0
        }
    }
}

// MARK: - KEvent

/// A kqueue event for registration or retrieval.
///
/// `KEvent` wraps the C `kevent` structure and provides a Swift-native
/// interface for working with kqueue events.
public struct KEvent: @unchecked Sendable {
    /// The underlying C kevent structure.
    internal var raw: kevent

    /// The filter type for this event.
    public var filter: KEventFilter {
        // Note: This is a simplified accessor. In practice, you'd need
        // to reconstruct the full filter from raw.filter, raw.ident, etc.
        // For now, we provide raw accessors.
        fatalError("Use rawFilter, rawIdent, etc. for reading returned events")
    }

    /// The raw filter type.
    public var rawFilter: Int16 { raw.filter }

    /// The raw identifier.
    public var rawIdent: UInt { raw.ident }

    /// The action flags.
    public var flags: KEventFlags {
        get { KEventFlags(rawValue: raw.flags) }
        set { raw.flags = newValue.rawValue }
    }

    /// The filter-specific flags.
    public var fflags: UInt32 {
        get { raw.fflags }
        set { raw.fflags = newValue }
    }

    /// The filter-specific data.
    public var data: Int {
        get { raw.data }
        set { raw.data = newValue }
    }

    /// User-defined opaque pointer.
    ///
    /// This pointer is passed through the kernel unchanged and can be
    /// used for callback dispatch or associating context with events.
    public var udata: UnsafeMutableRawPointer? {
        get { raw.udata }
        set { raw.udata = newValue }
    }

    /// Extended data fields.
    ///
    /// - `ext[0]` and `ext[1]` are filter-defined
    /// - `ext[2]` and `ext[3]` are user-defined
    public var ext: (UInt, UInt, UInt, UInt) {
        get { raw.ext }
        set { raw.ext = newValue }
    }

    // MARK: - Initialization

    /// Create an event from a filter specification.
    ///
    /// - Parameters:
    ///   - filter: The filter type and parameters
    ///   - flags: Action flags (default: `.add`)
    ///   - udata: Optional user data pointer
    public init(
        filter: KEventFilter,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) {
        self.raw = kevent(
            ident: filter.ident,
            filter: filter.rawFilter,
            flags: flags.rawValue,
            fflags: filter.fflags,
            data: filter.data,
            udata: udata,
            ext: (0, 0, 0, 0)
        )
    }

    /// Create an event from a raw C kevent structure.
    public init(raw: kevent) {
        self.raw = raw
    }

    // MARK: - Convenience Initializers

    /// Create a read event.
    public static func read(
        fd: Int32,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .read(fd: fd), flags: flags, udata: udata)
    }

    /// Create a write event.
    public static func write(
        fd: Int32,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .write(fd: fd), flags: flags, udata: udata)
    }

    /// Create a vnode event.
    public static func vnode(
        fd: Int32,
        events: VNodeEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .vnode(fd: fd, events: events), flags: flags, udata: udata)
    }

    /// Create a process event.
    public static func proc(
        pid: pid_t,
        events: ProcessEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .proc(pid: pid, events: events), flags: flags, udata: udata)
    }

    /// Create a signal event.
    public static func signal(
        _ signal: BSDSignal,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .signal(signal), flags: flags, udata: udata)
    }

    /// Create a timer event.
    public static func timer(
        id: UInt,
        timeout: Int64,
        unit: TimerUnit = .milliseconds,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .timer(id: id, value: timeout, unit: unit), flags: flags, udata: udata)
    }

    /// Create a one-shot timer event.
    public static func oneshotTimer(
        id: UInt,
        timeout: Int64,
        unit: TimerUnit = .milliseconds,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(
            filter: .timer(id: id, value: timeout, unit: unit),
            flags: [.add, .oneshot],
            udata: udata
        )
    }

    /// Create a user event.
    public static func user(
        id: UInt,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .user(id: id), flags: flags, udata: udata)
    }

    /// Create a jail event.
    public static func jail(
        jid: Int32,
        events: JailEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .jail(jid: jid, events: events), flags: flags, udata: udata)
    }

    /// Create a jail descriptor event.
    public static func jailDesc(
        fd: Int32,
        events: JailEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .jailDesc(fd: fd, events: events), flags: flags, udata: udata)
    }

    /// Create a process descriptor event.
    public static func procDesc(
        fd: Int32,
        events: ProcessEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent {
        KEvent(filter: .procDesc(fd: fd, events: events), flags: flags, udata: udata)
    }

    // MARK: - Delete Events

    /// Create a delete event for a filter.
    public static func delete(filter: KEventFilter) -> KEvent {
        KEvent(filter: filter, flags: .delete)
    }

    // MARK: - Descriptor-Based Convenience Initializers

    /// Create a read event for a descriptor.
    public static func read<D: Descriptor>(
        _ descriptor: borrowing D,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent where D: ~Copyable {
        descriptor.unsafe { fd in
            KEvent(filter: .read(fd: fd), flags: flags, udata: udata)
        }
    }

    /// Create a write event for a descriptor.
    public static func write<D: Descriptor>(
        _ descriptor: borrowing D,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent where D: ~Copyable {
        descriptor.unsafe { fd in
            KEvent(filter: .write(fd: fd), flags: flags, udata: udata)
        }
    }

    /// Create a vnode event for a descriptor.
    public static func vnode<D: Descriptor>(
        _ descriptor: borrowing D,
        events: VNodeEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent where D: ~Copyable {
        descriptor.unsafe { fd in
            KEvent(filter: .vnode(fd: fd, events: events), flags: flags, udata: udata)
        }
    }

    /// Create a process descriptor event.
    public static func proc<D: ProcessDescriptor>(
        _ descriptor: borrowing D,
        events: ProcessEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent where D: ~Copyable {
        descriptor.unsafe { fd in
            KEvent(filter: .procDesc(fd: fd, events: events), flags: flags, udata: udata)
        }
    }

    /// Create a jail descriptor event.
    public static func jail<D: JailDescriptor>(
        _ descriptor: borrowing D,
        events: JailEvents,
        flags: KEventFlags = .add,
        udata: UnsafeMutableRawPointer? = nil
    ) -> KEvent where D: ~Copyable {
        descriptor.unsafe { fd in
            KEvent(filter: .jailDesc(fd: fd, events: events), flags: flags, udata: udata)
        }
    }
}

// MARK: - Array Conversion

extension Array where Element == KEvent {
    /// Convert to an array of raw kevent structures.
    public var rawEvents: [kevent] {
        map { $0.raw }
    }
}

extension Array where Element == kevent {
    /// Convert to an array of KEvent wrappers.
    public var wrapped: [KEvent] {
        map { KEvent(raw: $0) }
    }
}
