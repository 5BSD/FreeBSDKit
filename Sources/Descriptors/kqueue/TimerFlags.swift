/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Glibc

/// Time unit and behavior flags for `EVFILT_TIMER`.
///
/// These flags are specified in the `fflags` field when registering
/// a timer event.
public struct TimerFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // MARK: - Time Units

    /// Interpret `data` as seconds.
    public static let seconds = TimerFlags(rawValue: UInt32(NOTE_SECONDS))

    /// Interpret `data` as milliseconds.
    ///
    /// This is the default if no time unit is specified.
    public static let milliseconds = TimerFlags(rawValue: UInt32(NOTE_MSECONDS))

    /// Interpret `data` as microseconds.
    public static let microseconds = TimerFlags(rawValue: UInt32(NOTE_USECONDS))

    /// Interpret `data` as nanoseconds.
    public static let nanoseconds = TimerFlags(rawValue: UInt32(NOTE_NSECONDS))

    // MARK: - Timer Behavior

    /// The `data` field specifies an absolute expiration time.
    ///
    /// Without this flag, `data` is a relative timeout/period.
    /// With this flag, `data` is an absolute time (using the system's
    /// monotonic clock). The timer fires once at the specified time
    /// and does not repeat.
    ///
    /// If the specified time is in the past, the event fires immediately.
    public static let absoluteTime = TimerFlags(rawValue: UInt32(NOTE_ABSTIME))
}

extension TimerFlags: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if contains(.seconds) { parts.append("seconds") }
        if contains(.milliseconds) { parts.append("milliseconds") }
        if contains(.microseconds) { parts.append("microseconds") }
        if contains(.nanoseconds) { parts.append("nanoseconds") }
        if contains(.absoluteTime) { parts.append("absoluteTime") }
        if parts.isEmpty { parts.append("milliseconds (default)") }
        return "TimerFlags([\(parts.joined(separator: ", "))])"
    }
}

// MARK: - Time Unit Enum

/// Time unit for timer events.
///
/// A more type-safe alternative to using `TimerFlags` directly for
/// specifying time units.
public enum TimerUnit: Sendable {
    case seconds
    case milliseconds
    case microseconds
    case nanoseconds

    /// Convert to the corresponding `TimerFlags` value.
    public var flags: TimerFlags {
        switch self {
        case .seconds: return .seconds
        case .milliseconds: return .milliseconds
        case .microseconds: return .microseconds
        case .nanoseconds: return .nanoseconds
        }
    }

    /// The multiplier to convert to nanoseconds.
    public var nanosPerUnit: UInt64 {
        switch self {
        case .seconds: return 1_000_000_000
        case .milliseconds: return 1_000_000
        case .microseconds: return 1_000
        case .nanoseconds: return 1
        }
    }
}
