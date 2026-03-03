/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc
import Foundation
import FreeBSDKit
import Jails

// MARK: - High-Level Registration API

public extension KqueueDescriptor where Self: ~Copyable {

    // MARK: - KEvent-based API

    /// Register events using the type-safe KEvent API.
    ///
    /// - Parameters:
    ///   - events: The events to register
    ///   - maxResults: Maximum number of results to return (0 for no results)
    ///   - timeout: Optional timeout; `nil` waits indefinitely
    /// - Returns: Array of event results
    @discardableResult
    func register(
        _ events: [KEvent],
        maxResults: Int = 0,
        timeout: TimeInterval? = 0
    ) throws -> [KEventResult] {
        let (count, raw) = try self.kevent(
            changes: events.rawEvents,
            maxEvents: maxResults,
            timeout: timeout
        )
        return KEventResult.parse(Array(raw.prefix(count)))
    }

    /// Register a single event using the type-safe KEvent API.
    @discardableResult
    func register(_ event: KEvent) throws -> [KEventResult] {
        try self.register([event], maxResults: 0, timeout: 0)
    }

    /// Wait for events and return parsed results.
    ///
    /// - Parameters:
    ///   - maxEvents: Maximum number of events to return
    ///   - timeout: Optional timeout; `nil` waits indefinitely
    /// - Returns: Array of event results
    func wait(maxEvents: Int = 16, timeout: TimeInterval? = nil) throws -> [KEventResult] {
        let (count, raw) = try self.kevent(
            changes: [],
            maxEvents: maxEvents,
            timeout: timeout
        )
        return KEventResult.parse(Array(raw.prefix(count)))
    }

    // MARK: - EVFILT_READ / EVFILT_WRITE

    /// Watch a file descriptor for read readiness.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor to watch
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func watchReadable(
        _ fd: Int32,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.read(fd: fd, flags: flags, udata: udata))
    }

    /// Watch a descriptor for read readiness.
    func watchReadable(
        _ descriptor: borrowing some Descriptor & ~Copyable,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try descriptor.unsafe { fd in
            try watchReadable(fd, flags: flags, udata: udata)
        }
    }

    /// Watch a file descriptor for write readiness.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor to watch
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func watchWritable(
        _ fd: Int32,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.write(fd: fd, flags: flags, udata: udata))
    }

    /// Watch a descriptor for write readiness.
    func watchWritable(
        _ descriptor: borrowing some Descriptor & ~Copyable,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try descriptor.unsafe { fd in
            try watchWritable(fd, flags: flags, udata: udata)
        }
    }

    /// Stop watching a file descriptor for read readiness.
    func unwatchReadable(_ fd: Int32) throws {
        try register(KEvent.delete(filter: .read(fd: fd)))
    }

    /// Stop watching a descriptor for read readiness.
    func unwatchReadable(_ descriptor: borrowing some Descriptor & ~Copyable) throws {
        try descriptor.unsafe { fd in
            try unwatchReadable(fd)
        }
    }

    /// Stop watching a file descriptor for write readiness.
    func unwatchWritable(_ fd: Int32) throws {
        try register(KEvent.delete(filter: .write(fd: fd)))
    }

    /// Stop watching a descriptor for write readiness.
    func unwatchWritable(_ descriptor: borrowing some Descriptor & ~Copyable) throws {
        try descriptor.unsafe { fd in
            try unwatchWritable(fd)
        }
    }

    // MARK: - EVFILT_VNODE

    /// Watch a file or directory for changes.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor to watch
    ///   - events: The vnode events to watch for
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func watchFile(
        _ fd: Int32,
        events: VNodeEvents,
        flags: KEventFlags = [.add, .enable, .clear],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.vnode(fd: fd, events: events, flags: flags, udata: udata))
    }

    /// Watch a descriptor for changes.
    func watchFile(
        _ descriptor: borrowing some Descriptor & ~Copyable,
        events: VNodeEvents,
        flags: KEventFlags = [.add, .enable, .clear],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try descriptor.unsafe { fd in
            try watchFile(fd, events: events, flags: flags, udata: udata)
        }
    }

    /// Stop watching a file descriptor for changes.
    func unwatchFile(_ fd: Int32) throws {
        try register(KEvent.delete(filter: .vnode(fd: fd, events: [])))
    }

    /// Stop watching a descriptor for changes.
    func unwatchFile(_ descriptor: borrowing some Descriptor & ~Copyable) throws {
        try descriptor.unsafe { fd in
            try unwatchFile(fd)
        }
    }

    // MARK: - EVFILT_PROC

    /// Watch a process for lifecycle events.
    ///
    /// - Parameters:
    ///   - pid: The process ID to watch
    ///   - events: The process events to watch for
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func watchProcess(
        _ pid: pid_t,
        events: ProcessEvents,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.proc(pid: pid, events: events, flags: flags, udata: udata))
    }

    /// Watch a process descriptor for lifecycle events.
    func watchProcess(
        _ descriptor: borrowing some Descriptor & ~Copyable,
        events: ProcessEvents,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try descriptor.unsafe { fd in
            let ev = KEvent(
                filter: .procDesc(fd: fd, events: events),
                flags: flags,
                udata: udata
            )
            try register(ev)
        }
    }

    /// Stop watching a process.
    func unwatchProcess(_ pid: pid_t) throws {
        try register(KEvent.delete(filter: .proc(pid: pid, events: [])))
    }

    /// Stop watching a process descriptor.
    func unwatchProcess(_ descriptor: borrowing some Descriptor & ~Copyable) throws {
        _ = try descriptor.unsafe { fd in
            try register(KEvent.delete(filter: .procDesc(fd: fd, events: [])))
        }
    }

    // MARK: - EVFILT_TIMER

    /// Add a repeating timer.
    ///
    /// - Parameters:
    ///   - id: User-defined identifier for the timer
    ///   - interval: The timer interval
    ///   - unit: The time unit for `interval`
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func addTimer(
        id: UInt,
        interval: Int64,
        unit: TimerUnit = .milliseconds,
        flags: KEventFlags = [.add, .enable],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.timer(id: id, timeout: interval, unit: unit, flags: flags, udata: udata))
    }

    /// Add a one-shot timer.
    ///
    /// - Parameters:
    ///   - id: User-defined identifier for the timer
    ///   - timeout: The timeout value
    ///   - unit: The time unit for `timeout`
    ///   - udata: Optional user data pointer
    func addOneshotTimer(
        id: UInt,
        timeout: Int64,
        unit: TimerUnit = .milliseconds,
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.oneshotTimer(id: id, timeout: timeout, unit: unit, udata: udata))
    }

    /// Cancel a timer.
    func cancelTimer(id: UInt) throws {
        try register(KEvent.delete(filter: .timer(id: id, value: 0)))
    }

    // MARK: - EVFILT_USER

    /// Add a user-defined event.
    ///
    /// - Parameters:
    ///   - id: User-defined identifier for the event
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func addUserEvent(
        id: UInt,
        flags: KEventFlags = [.add, .enable, .clear],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.user(id: id, flags: flags, udata: udata))
    }

    /// Trigger a user-defined event.
    ///
    /// - Parameter id: The event identifier to trigger
    func triggerUserEvent(id: UInt) throws {
        let ev = KEvent(
            filter: .user(id: id, trigger: true),
            flags: .enable
        )
        try register(ev)
    }

    /// Remove a user-defined event.
    func removeUserEvent(id: UInt) throws {
        try register(KEvent.delete(filter: .user(id: id)))
    }

    // MARK: - EVFILT_JAIL / EVFILT_JAILDESC

    /// Watch a jail for state changes.
    ///
    /// - Parameters:
    ///   - jid: The jail ID to watch (0 for current jail)
    ///   - events: The jail events to watch for
    ///   - flags: Event flags (default: add and enable)
    ///   - udata: Optional user data pointer
    func watchJail(
        _ jid: Int32,
        events: JailEvents,
        flags: KEventFlags = [.add, .enable, .clear],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        try register(KEvent.jail(jid: jid, events: events, flags: flags, udata: udata))
    }

    /// Watch a jail descriptor for state changes.
    func watchJail(
        _ descriptor: borrowing some JailDescriptor & ~Copyable,
        events: JailEvents,
        flags: KEventFlags = [.add, .enable, .clear],
        udata: UnsafeMutableRawPointer? = nil
    ) throws {
        _ = try descriptor.unsafe { fd in
            try register(KEvent.jailDesc(fd: fd, events: events, flags: flags, udata: udata))
        }
    }

    /// Stop watching a jail.
    func unwatchJail(_ jid: Int32) throws {
        try register(KEvent.delete(filter: .jail(jid: jid, events: [])))
    }

    /// Stop watching a jail descriptor.
    func unwatchJail(_ descriptor: borrowing some JailDescriptor & ~Copyable) throws {
        _ = try descriptor.unsafe { fd in
            try register(KEvent.delete(filter: .jailDesc(fd: fd, events: [])))
        }
    }
}
