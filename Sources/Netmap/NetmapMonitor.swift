/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation

/// Monitor mode utilities for packet sniffing.
///
/// Netmap monitor mode allows you to observe packets passing through
/// another netmap port without affecting the original traffic flow.
///
/// ## Monitor Modes
///
/// - **Copy mode**: Packets are copied to the monitor port. Slightly
///   slower but doesn't affect the monitored port.
///
/// - **Zero-copy mode**: Shares buffer references with monitored port.
///   Faster but requires careful handling of buffer lifecycles.
///
/// ## Example: TX Monitor
///
/// ```swift
/// // Monitor all transmissions on em0
/// let monitor = try NetmapMonitor.openTxMonitor(
///     interface: "em0",
///     ringId: 0  // Monitor ring 0
/// )
///
/// // Capture transmitted packets
/// while true {
///     let packets = try monitor.port.receivePackets()
///     for packet in packets {
///         print("TX: \(packet.count) bytes")
///     }
/// }
/// ```
///
/// ## Example: RX Monitor
///
/// ```swift
/// // Monitor all received packets on em0
/// let monitor = try NetmapMonitor.openRxMonitor(
///     interface: "em0",
///     zeroCopy: true  // Use zero-copy for performance
/// )
/// ```
public struct NetmapMonitor: ~Copyable {

    /// The underlying netmap port.
    public var port: NetmapPort

    /// Whether this is a zero-copy monitor.
    public let isZeroCopy: Bool

    /// Whether monitoring TX or RX.
    public let direction: Direction

    /// Monitor direction.
    public enum Direction: Sendable {
        case tx
        case rx
        case both
    }

    // MARK: - Opening Monitors

    /// Opens a TX monitor on the specified interface.
    ///
    /// A TX monitor receives copies of all packets transmitted on the
    /// monitored interface.
    ///
    /// - Parameters:
    ///   - interface: The interface to monitor (e.g., "em0")
    ///   - ringId: Specific ring to monitor (0 for first ring)
    ///   - zeroCopy: Use zero-copy mode (default: false)
    /// - Returns: A monitor port
    /// - Throws: `NetmapError` if opening fails
    public static func openTxMonitor(
        interface: String,
        ringId: UInt16 = 0,
        zeroCopy: Bool = false
    ) throws -> NetmapMonitor {
        var flags: NetmapRegistrationFlags = [.monitorTX]
        if zeroCopy {
            flags.insert(.zeroCopyMonitor)
        }

        let port = try NetmapPort.open(
            interface: interface,
            mode: .oneNIC,
            flags: flags,
            ringId: ringId
        )

        return NetmapMonitor(port: port, isZeroCopy: zeroCopy, direction: .tx)
    }

    /// Opens an RX monitor on the specified interface.
    ///
    /// An RX monitor receives copies of all packets received on the
    /// monitored interface.
    ///
    /// - Parameters:
    ///   - interface: The interface to monitor (e.g., "em0")
    ///   - ringId: Specific ring to monitor (0 for first ring)
    ///   - zeroCopy: Use zero-copy mode (default: false)
    /// - Returns: A monitor port
    /// - Throws: `NetmapError` if opening fails
    public static func openRxMonitor(
        interface: String,
        ringId: UInt16 = 0,
        zeroCopy: Bool = false
    ) throws -> NetmapMonitor {
        var flags: NetmapRegistrationFlags = [.monitorRX]
        if zeroCopy {
            flags.insert(.zeroCopyMonitor)
        }

        let port = try NetmapPort.open(
            interface: interface,
            mode: .oneNIC,
            flags: flags,
            ringId: ringId
        )

        return NetmapMonitor(port: port, isZeroCopy: zeroCopy, direction: .rx)
    }

    /// Opens a bidirectional monitor on the specified interface.
    ///
    /// A bidirectional monitor receives copies of all packets both
    /// transmitted and received on the monitored interface.
    ///
    /// - Parameters:
    ///   - interface: The interface to monitor (e.g., "em0")
    ///   - zeroCopy: Use zero-copy mode (default: false)
    /// - Returns: A monitor port
    /// - Throws: `NetmapError` if opening fails
    public static func openBidirectional(
        interface: String,
        zeroCopy: Bool = false
    ) throws -> NetmapMonitor {
        var flags: NetmapRegistrationFlags = [.monitorTX, .monitorRX]
        if zeroCopy {
            flags.insert(.zeroCopyMonitor)
        }

        let port = try NetmapPort.open(
            interface: interface,
            mode: .allNIC,
            flags: flags
        )

        return NetmapMonitor(port: port, isZeroCopy: zeroCopy, direction: .both)
    }

    // MARK: - Private Init

    private init(port: consuming NetmapPort, isZeroCopy: Bool, direction: Direction) {
        self.port = port
        self.isZeroCopy = isZeroCopy
        self.direction = direction
    }

    // MARK: - Capture Methods

    /// Captures packets with a handler.
    ///
    /// This is a convenience wrapper around the port's receive methods,
    /// optimized for monitoring use cases.
    ///
    /// - Parameters:
    ///   - timeout: Poll timeout in milliseconds
    ///   - handler: Called for each captured packet, return false to stop
    /// - Throws: `NetmapError` if capture fails
    public func capture(
        timeout: Int32 = 1000,
        handler: (Data, Direction) throws -> Bool
    ) throws {
        while true {
            let packets = try port.receivePackets(timeout: timeout)

            for packet in packets {
                if try !handler(packet, direction) {
                    return
                }
            }
        }
    }
}
