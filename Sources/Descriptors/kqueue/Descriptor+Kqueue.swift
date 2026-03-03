/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc
import Foundation
import FreeBSDKit
import Jails

// MARK: - ProcessDescriptor + Kqueue

public extension ProcessDescriptor where Self: ~Copyable {

    /// Wait for the process using a typed kqueue event.
    ///
    /// This is similar to `wait()` but returns the raw `KEventResult`
    /// instead of decoding the exit status. Useful when you want to
    /// monitor multiple events or integrate with a kqueue event loop.
    ///
    /// - Parameter kq: The kqueue to use for waiting
    /// - Returns: The process event result
    func waitEvent(using kq: borrowing some KqueueDescriptor & ~Copyable) throws -> KEventResult {
        try self.unsafe { fd in
            try kq.register(KEvent.procDesc(fd: fd, events: .exit, flags: [.add, .enable, .oneshot]))

            let results = try kq.wait(maxEvents: 1)
            guard let result = results.first else {
                throw POSIXError(.ECHILD)
            }
            return result
        }
    }
}

// MARK: - JailDescriptor + Kqueue

public extension JailDescriptor where Self: ~Copyable {

    /// Watch this jail for events using a kqueue.
    ///
    /// - Parameters:
    ///   - kq: The kqueue to register with
    ///   - events: The jail events to watch for
    ///   - flags: Event flags (default: add, enable, clear)
    func watch(
        using kq: borrowing some KqueueDescriptor & ~Copyable,
        events: JailEvents = .all,
        flags: KEventFlags = [.add, .enable, .clear]
    ) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.jailDesc(fd: fd, events: events, flags: flags))
        }
    }

    /// Stop watching this jail.
    func unwatch(using kq: borrowing some KqueueDescriptor & ~Copyable) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.delete(filter: .jailDesc(fd: fd, events: [])))
        }
    }
}

// MARK: - Descriptor + Kqueue (I/O Readiness)

public extension Descriptor where Self: ~Copyable {

    /// Watch this descriptor for read readiness.
    ///
    /// - Parameters:
    ///   - kq: The kqueue to register with
    ///   - flags: Event flags (default: add and enable)
    func watchReadable(
        using kq: borrowing some KqueueDescriptor & ~Copyable,
        flags: KEventFlags = [.add, .enable]
    ) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.read(fd: fd, flags: flags))
        }
    }

    /// Watch this descriptor for write readiness.
    ///
    /// - Parameters:
    ///   - kq: The kqueue to register with
    ///   - flags: Event flags (default: add and enable)
    func watchWritable(
        using kq: borrowing some KqueueDescriptor & ~Copyable,
        flags: KEventFlags = [.add, .enable]
    ) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.write(fd: fd, flags: flags))
        }
    }

    /// Stop watching this descriptor for read readiness.
    func unwatchReadable(using kq: borrowing some KqueueDescriptor & ~Copyable) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.delete(filter: .read(fd: fd)))
        }
    }

    /// Stop watching this descriptor for write readiness.
    func unwatchWritable(using kq: borrowing some KqueueDescriptor & ~Copyable) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.delete(filter: .write(fd: fd)))
        }
    }
}

// MARK: - FileDescriptor + Kqueue (VNode)

public extension FileDescriptor where Self: ~Copyable {

    /// Watch this file for changes.
    ///
    /// - Parameters:
    ///   - kq: The kqueue to register with
    ///   - events: The vnode events to watch for
    ///   - flags: Event flags (default: add, enable, clear)
    func watch(
        using kq: borrowing some KqueueDescriptor & ~Copyable,
        events: VNodeEvents = .all,
        flags: KEventFlags = [.add, .enable, .clear]
    ) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.vnode(fd: fd, events: events, flags: flags))
        }
    }

    /// Stop watching this file.
    func unwatch(using kq: borrowing some KqueueDescriptor & ~Copyable) throws {
        _ = try self.unsafe { fd in
            try kq.register(KEvent.delete(filter: .vnode(fd: fd, events: [])))
        }
    }
}
