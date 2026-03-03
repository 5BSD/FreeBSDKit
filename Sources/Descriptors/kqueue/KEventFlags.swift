/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc

/// Action flags for kqueue events.
///
/// These flags control how events are registered, modified, and returned
/// from `kevent()`.
public struct KEventFlags: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    // MARK: - Registration Flags

    /// Add the event to the kqueue.
    ///
    /// Re-adding an existing event modifies its parameters without
    /// creating a duplicate. The event is automatically enabled unless
    /// `.disable` is also specified.
    public static let add = KEventFlags(rawValue: UInt16(EV_ADD))

    /// Remove the event from the kqueue.
    public static let delete = KEventFlags(rawValue: UInt16(EV_DELETE))

    /// Enable the event, permitting `kevent()` to return it when triggered.
    public static let enable = KEventFlags(rawValue: UInt16(EV_ENABLE))

    /// Disable the event so `kevent()` will not return it.
    ///
    /// The filter itself remains active; the event just won't be reported.
    public static let disable = KEventFlags(rawValue: UInt16(EV_DISABLE))

    // MARK: - Delivery Flags

    /// Return only the first occurrence, then delete the event.
    ///
    /// The event is automatically removed after being retrieved.
    public static let oneshot = KEventFlags(rawValue: UInt16(EV_ONESHOT))

    /// Reset the event state after retrieval.
    ///
    /// Useful for filters that report state transitions. After the event
    /// is retrieved, the state is reset so subsequent transitions can
    /// be detected.
    public static let clear = KEventFlags(rawValue: UInt16(EV_CLEAR))

    /// Disable the event source immediately after delivery.
    ///
    /// Similar to `.oneshot` but the event remains registered (just disabled).
    /// Re-enable with a subsequent `kevent()` call using `.enable`.
    public static let dispatch = KEventFlags(rawValue: UInt16(EV_DISPATCH))

    // MARK: - Bulk Operation Flags

    /// Force `EV_ERROR` to be returned for bulk change verification.
    ///
    /// When processing a changelist, this forces an `EV_ERROR` event to be
    /// placed in the eventlist with `data` set to 0 on success, or the
    /// error code on failure. Useful for verifying bulk registrations.
    public static let receipt = KEventFlags(rawValue: UInt16(EV_RECEIPT))

    /// Preserve the `udata` value when modifying an existing event.
    ///
    /// Allows changing event parameters without needing to know the
    /// previously registered `udata` value. Cannot be combined with `.add`.
    public static let keepUdata = KEventFlags(rawValue: UInt16(EV_KEEPUDATA))

    // MARK: - Output Flags (set by kernel)

    /// End-of-file condition detected.
    ///
    /// Set by the kernel to indicate a filter-specific EOF condition.
    /// For sockets, indicates the read direction has shut down.
    /// For pipes/fifos, indicates the last writer disconnected.
    public static let eof = KEventFlags(rawValue: UInt16(EV_EOF))

    /// Error condition.
    ///
    /// Set by the kernel when an error occurred processing the event.
    /// The `data` field contains the error code.
    public static let error = KEventFlags(rawValue: UInt16(EV_ERROR))
}

extension KEventFlags: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if contains(.add) { parts.append("add") }
        if contains(.delete) { parts.append("delete") }
        if contains(.enable) { parts.append("enable") }
        if contains(.disable) { parts.append("disable") }
        if contains(.oneshot) { parts.append("oneshot") }
        if contains(.clear) { parts.append("clear") }
        if contains(.dispatch) { parts.append("dispatch") }
        if contains(.receipt) { parts.append("receipt") }
        if contains(.keepUdata) { parts.append("keepUdata") }
        if contains(.eof) { parts.append("eof") }
        if contains(.error) { parts.append("error") }
        return "KEventFlags([\(parts.joined(separator: ", "))])"
    }
}
