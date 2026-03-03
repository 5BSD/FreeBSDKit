/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc

/// Events for monitoring files and directories via `EVFILT_VNODE`.
///
/// These events are specified in the `fflags` field when registering
/// a vnode filter, and returned in `fflags` to indicate which events
/// occurred.
public struct VNodeEvents: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // MARK: - File Content Events

    /// A write occurred on the file.
    public static let write = VNodeEvents(rawValue: UInt32(NOTE_WRITE))

    /// The file was extended.
    ///
    /// For directories, this indicates an entry was added or removed
    /// (but not renamed within the directory).
    public static let extend = VNodeEvents(rawValue: UInt32(NOTE_EXTEND))

    /// A read occurred on the file.
    public static let read = VNodeEvents(rawValue: UInt32(NOTE_READ))

    // MARK: - File Metadata Events

    /// File attributes changed.
    ///
    /// Includes changes to permissions, timestamps, link count, etc.
    public static let attrib = VNodeEvents(rawValue: UInt32(NOTE_ATTRIB))

    /// The link count changed.
    ///
    /// For directories, this indicates a subdirectory was created or deleted.
    public static let link = VNodeEvents(rawValue: UInt32(NOTE_LINK))

    // MARK: - File Lifecycle Events

    /// The file was deleted (`unlink()` was called).
    public static let delete = VNodeEvents(rawValue: UInt32(NOTE_DELETE))

    /// The file was renamed.
    public static let rename = VNodeEvents(rawValue: UInt32(NOTE_RENAME))

    /// Access to the file was revoked.
    ///
    /// This occurs via `revoke(2)` or when the filesystem is unmounted.
    public static let revoke = VNodeEvents(rawValue: UInt32(NOTE_REVOKE))

    // MARK: - File Descriptor Events

    /// The file was opened.
    public static let open = VNodeEvents(rawValue: UInt32(NOTE_OPEN))

    /// A file descriptor referencing this file was closed (without write access).
    public static let close = VNodeEvents(rawValue: UInt32(NOTE_CLOSE))

    /// A file descriptor with write access was closed.
    ///
    /// - Note: Not activated on forcible close via unmount or revoke;
    ///   `revoke` is sent instead.
    public static let closeWrite = VNodeEvents(rawValue: UInt32(NOTE_CLOSE_WRITE))

    // MARK: - Special Flags

    /// Trigger the event unconditionally (like `poll(2)` behavior).
    ///
    /// Normally vnode events only fire when the file pointer is not at EOF.
    /// This flag makes the filter fire regardless.
    public static let filePoll = VNodeEvents(rawValue: UInt32(NOTE_FILE_POLL))

    // MARK: - Common Combinations

    /// All modification events (write, extend, attrib, link).
    public static let modifications: VNodeEvents = [.write, .extend, .attrib, .link]

    /// All lifecycle events (delete, rename, revoke).
    public static let lifecycle: VNodeEvents = [.delete, .rename, .revoke]

    /// All open/close events.
    public static let openClose: VNodeEvents = [.open, .close, .closeWrite]

    /// All events.
    public static let all: VNodeEvents = [
        .write, .extend, .read, .attrib, .link,
        .delete, .rename, .revoke,
        .open, .close, .closeWrite
    ]
}

extension VNodeEvents: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if contains(.write) { parts.append("write") }
        if contains(.extend) { parts.append("extend") }
        if contains(.read) { parts.append("read") }
        if contains(.attrib) { parts.append("attrib") }
        if contains(.link) { parts.append("link") }
        if contains(.delete) { parts.append("delete") }
        if contains(.rename) { parts.append("rename") }
        if contains(.revoke) { parts.append("revoke") }
        if contains(.open) { parts.append("open") }
        if contains(.close) { parts.append("close") }
        if contains(.closeWrite) { parts.append("closeWrite") }
        if contains(.filePoll) { parts.append("filePoll") }
        return "VNodeEvents([\(parts.joined(separator: ", "))])"
    }
}
