/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation

/// Host ring access utilities.
///
/// Host rings provide access to packets traveling between the NIC and
/// the host networking stack. This is useful for:
///
/// - Injecting packets into the host stack
/// - Intercepting packets from applications before they reach the NIC
/// - Building hybrid applications that use both netmap and regular sockets
///
/// ## Host Ring Architecture
///
/// ```
/// Application
///     │
///     ▼
/// ┌─────────────────┐
/// │   Host Stack    │
/// │  (TCP/IP, etc)  │
/// └────────┬────────┘
///          │
///     Host Rings ◄── You can intercept here
///          │
/// ┌────────┴────────┐
/// │    NIC Rings    │
/// └────────┬────────┘
///          │
///          ▼
///        Network
/// ```
///
/// ## Example: Host Stack Interceptor
///
/// ```swift
/// // Open in NIC+Host mode to access both
/// let port = try NetmapPort.open(
///     interface: "em0",
///     mode: .nicAndHost
/// )
///
/// // Access host rings
/// let hostTxCount = port.hostTxRingCount
/// let hostRxCount = port.hostRxRingCount
///
/// // Process host->NIC packets
/// for i in 0..<hostTxCount {
///     let ring = port.hostTxRing(i)
///     while !ring.isEmpty {
///         let slot = ring.currentSlot
///         let packet = ring.bufferData(for: slot)
///         print("Host sending: \(packet.count) bytes")
///         ring.advance()
///     }
/// }
/// ```
public enum NetmapHost {

    // MARK: - Host Mode Port Opening

    /// Opens a port with host ring access only.
    ///
    /// This mode provides access only to packets going to/from the host
    /// stack, not the actual NIC traffic.
    ///
    /// - Parameter interface: The interface name
    /// - Returns: A netmap port with host ring access
    /// - Throws: `NetmapError` if opening fails
    public static func openHostOnly(interface: String) throws -> NetmapPort {
        return try NetmapPort.open(
            interface: interface,
            mode: .hostOnly
        )
    }

    /// Opens a port with both NIC and host ring access.
    ///
    /// This mode provides access to:
    /// - NIC rings: Direct hardware access
    /// - Host rings: Packets to/from host stack
    ///
    /// - Parameter interface: The interface name
    /// - Returns: A netmap port with full access
    /// - Throws: `NetmapError` if opening fails
    public static func openNICAndHost(interface: String) throws -> NetmapPort {
        return try NetmapPort.open(
            interface: interface,
            mode: .nicAndHost
        )
    }

    /// Opens a single host ring.
    ///
    /// - Parameters:
    ///   - interface: The interface name
    ///   - ringId: The host ring index
    /// - Returns: A netmap port for a single host ring
    /// - Throws: `NetmapError` if opening fails
    public static func openSingleHostRing(
        interface: String,
        ringId: UInt16
    ) throws -> NetmapPort {
        return try NetmapPort.open(
            interface: interface,
            mode: .oneHost,
            ringId: ringId
        )
    }
}

// MARK: - Host Ring Utilities

extension NetmapHost {

    /// Injects a packet into the host stack.
    ///
    /// The packet will appear to applications as if it was received
    /// from the network.
    ///
    /// - Parameters:
    ///   - packet: The packet data to inject
    ///   - port: A port with host ring access
    ///   - ringIndex: Which host RX ring to use (default: 0)
    /// - Returns: true if injection succeeded
    /// - Throws: `NetmapError` if sync fails
    @discardableResult
    public static func injectToHost(
        packet: Data,
        port: borrowing NetmapPort,
        ringIndex: UInt32 = 0
    ) throws -> Bool {
        guard ringIndex < port.hostRxRingCount else {
            return false
        }

        let ring = port.hostRxRing(ringIndex)
        guard ring.hasSpace else {
            return false
        }

        var slot = ring.currentSlot
        ring.setBuffer(for: &slot, data: packet)
        ring.advance()

        try port.rxSync()
        return true
    }

    /// Intercepts packets going from host to NIC.
    ///
    /// - Parameters:
    ///   - port: A port with host ring access
    ///   - handler: Called for each intercepted packet
    /// - Returns: Number of packets intercepted
    public static func interceptFromHost(
        port: borrowing NetmapPort,
        handler: (Data) throws -> Void
    ) throws -> Int {
        var count = 0

        for i in 0..<port.hostTxRingCount {
            let ring = port.hostTxRing(i)

            while !ring.isEmpty {
                let slot = ring.currentSlot
                let data = ring.bufferData(for: slot)
                try handler(data)
                ring.advance()
                count += 1
            }
        }

        return count
    }
}
