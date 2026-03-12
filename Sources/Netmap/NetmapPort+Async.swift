/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation
import Glibc

/// Async extensions for NetmapPort.
///
/// These methods provide async/await style packet I/O using poll().
/// For integration with kqueue event loops, use `port.fileDescriptor`
/// directly with the Descriptors module's KqueueDescriptor.
///
/// ## Example: Async Packet Processing
///
/// ```swift
/// var port = try NetmapPort.open(interface: "vale0:async")
///
/// // Async receive loop
/// while true {
///     let packets = try await port.receivePackets()
///     for packet in packets {
///         print("Received \(packet.count) bytes")
///     }
/// }
/// ```
///
/// ## KQueue Integration
///
/// For event-driven I/O with kqueue:
///
/// ```swift
/// let port = try NetmapPort.open(interface: "vale0:kq")
/// let kq = try OwnedFD.makeKqueue()
///
/// // Watch for read readiness
/// try kq.watchReadable(port.fileDescriptor)
///
/// // Event loop
/// while true {
///     let events = try kq.wait(maxEvents: 16)
///     for event in events {
///         if event.ident == UInt(port.fileDescriptor) {
///             // Port is readable
///             try port.rxSync()
///             // Process packets...
///         }
///     }
/// }
/// ```
extension NetmapPort {

    // MARK: - Async Receive

    /// Waits asynchronously for packets and returns them.
    ///
    /// This method polls for incoming packets with the specified timeout,
    /// then syncs and collects all available packets from all RX rings.
    ///
    /// - Parameter timeout: Timeout in milliseconds (-1 for infinite, default 1000ms)
    /// - Returns: Array of received packet data
    /// - Throws: `NetmapError` if the operation fails
    public func receivePackets(timeout: Int32 = 1000) throws -> [Data] {
        // Wait for RX readiness
        let ready = try waitForRx(timeout: timeout)
        guard ready else { return [] }

        // Sync and collect packets
        try rxSync()

        var packets: [Data] = []

        for ringIdx in 0..<rxRingCount {
            let ring = rxRing(ringIdx)

            while !ring.isEmpty {
                let slot = ring.currentSlot
                let data = ring.bufferData(for: slot)
                packets.append(data)
                ring.advance()
            }
        }

        return packets
    }

    /// Waits asynchronously for a single packet.
    ///
    /// - Parameter timeout: Timeout in milliseconds (-1 for infinite, default 1000ms)
    /// - Returns: The received packet data, or nil if timeout
    /// - Throws: `NetmapError` if the operation fails
    public func receivePacket(timeout: Int32 = 1000) throws -> Data? {
        let ready = try waitForRx(timeout: timeout)
        guard ready else { return nil }

        try rxSync()

        // Find first available packet
        for ringIdx in 0..<rxRingCount {
            let ring = rxRing(ringIdx)

            if !ring.isEmpty {
                let slot = ring.currentSlot
                let data = ring.bufferData(for: slot)
                ring.advance()
                return data
            }
        }

        return nil
    }

    // MARK: - Async Transmit

    /// Sends a packet asynchronously, waiting for TX space if needed.
    ///
    /// - Parameters:
    ///   - data: The packet data to send
    ///   - timeout: Timeout in milliseconds for waiting for TX space
    /// - Returns: true if the packet was sent, false if timeout
    /// - Throws: `NetmapError` if the operation fails
    @discardableResult
    public func sendPacket(_ data: Data, timeout: Int32 = 1000) throws -> Bool {
        // Find a ring with space
        for ringIdx in 0..<txRingCount {
            let ring = txRing(ringIdx)

            if ring.hasSpace {
                var slot = ring.currentSlot
                ring.setBuffer(for: &slot, data: data)
                ring.advance()
                try txSync()
                return true
            }
        }

        // No space, wait for it
        let ready = try waitForTx(timeout: timeout)
        guard ready else { return false }

        // Try again
        for ringIdx in 0..<txRingCount {
            let ring = txRing(ringIdx)

            if ring.hasSpace {
                var slot = ring.currentSlot
                ring.setBuffer(for: &slot, data: data)
                ring.advance()
                try txSync()
                return true
            }
        }

        return false
    }

    /// Sends multiple packets asynchronously.
    ///
    /// Packets are sent in order, filling TX rings as space becomes available.
    /// Returns the number of packets actually sent.
    ///
    /// - Parameters:
    ///   - packets: Array of packet data to send
    ///   - timeout: Timeout in milliseconds for waiting for TX space
    /// - Returns: Number of packets successfully sent
    /// - Throws: `NetmapError` if the operation fails
    public func sendPackets(_ packets: [Data], timeout: Int32 = 1000) throws -> Int {
        var sent = 0

        for packet in packets {
            if try sendPacket(packet, timeout: timeout) {
                sent += 1
            } else {
                break  // Timeout, stop trying
            }
        }

        return sent
    }

    // MARK: - Batch Operations

    /// Processes packets in a batch with a handler closure.
    ///
    /// This is more efficient than `receivePackets()` when you don't need
    /// to keep the packet data, as it avoids copying data into Swift arrays.
    ///
    /// - Parameters:
    ///   - timeout: Timeout in milliseconds for waiting for packets
    ///   - handler: Closure called for each packet with ring index and slot
    /// - Returns: Number of packets processed
    /// - Throws: `NetmapError` if the operation fails
    @discardableResult
    public func processPackets(
        timeout: Int32 = 1000,
        handler: (UInt32, NetmapSlot, Data) throws -> Void
    ) throws -> Int {
        let ready = try waitForRx(timeout: timeout)
        guard ready else { return 0 }

        try rxSync()

        var count = 0

        for ringIdx in 0..<rxRingCount {
            let ring = rxRing(ringIdx)

            while !ring.isEmpty {
                let slot = ring.currentSlot
                let data = ring.bufferData(for: slot)
                try handler(ringIdx, slot, data)
                ring.advance()
                count += 1
            }
        }

        return count
    }

    // MARK: - Event Loop Support

    /// Creates a simple packet processing loop.
    ///
    /// This method runs an infinite loop that receives packets and calls
    /// the handler for each one. Use this for simple packet processing
    /// applications.
    ///
    /// - Parameters:
    ///   - pollTimeout: Poll timeout in milliseconds per iteration
    ///   - handler: Closure called for each received packet
    /// - Throws: `NetmapError` if an I/O operation fails
    public func runReceiveLoop(
        pollTimeout: Int32 = 100,
        handler: (Data) throws -> Bool
    ) throws {
        while true {
            let packets = try receivePackets(timeout: pollTimeout)

            for packet in packets {
                if try !handler(packet) {
                    return  // Handler requested stop
                }
            }
        }
    }
}
