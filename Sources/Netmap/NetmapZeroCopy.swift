/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation

/// Zero-copy packet forwarding utilities.
///
/// These helpers enable high-performance packet forwarding by swapping
/// buffer indices between slots instead of copying packet data.
///
/// ## Zero-Copy Forwarding
///
/// The basic idea is to swap buffer indices between RX and TX slots:
///
/// ```swift
/// let rxRing = srcPort.rxRing(0)
/// let txRing = dstPort.txRing(0)
///
/// while !rxRing.isEmpty && txRing.hasSpace {
///     var rxSlot = rxRing.currentSlot
///     var txSlot = txRing.currentSlot
///
///     // Swap buffers (zero-copy)
///     NetmapZeroCopy.swapBuffers(&rxSlot, &txSlot)
///
///     rxRing.advance()
///     txRing.advance()
/// }
/// ```
///
/// ## Performance Considerations
///
/// Zero-copy forwarding is much faster than copying packets because:
/// - No memory copy of packet data
/// - Only updates buffer index and length fields
/// - Takes ~10-20 nanoseconds vs ~100+ nanoseconds for copy
///
/// However, zero-copy requires:
/// - Both ports share the same memory region (same memory ID)
/// - Care with buffer lifetime (don't use swapped buffer until TX completes)
public enum NetmapZeroCopy {

    // MARK: - Buffer Swapping

    /// Swaps buffer indices between two slots for zero-copy forwarding.
    ///
    /// After swapping, the TX slot will reference the RX buffer and vice versa.
    /// Both slots are marked with `.bufferChanged` to notify netmap.
    ///
    /// - Parameters:
    ///   - slot1: First slot (typically RX)
    ///   - slot2: Second slot (typically TX)
    ///   - copyLength: If true, copy length from slot1 to slot2
    public static func swapBuffers(
        _ slot1: inout NetmapSlot,
        _ slot2: inout NetmapSlot,
        copyLength: Bool = true
    ) {
        let buf1 = slot1.bufferIndex
        let buf2 = slot2.bufferIndex

        slot1.bufferIndex = buf2
        slot2.bufferIndex = buf1

        if copyLength {
            slot2.length = slot1.length
        }

        slot1.markBufferChanged()
        slot2.markBufferChanged()
    }

    /// Moves a buffer from source slot to destination slot.
    ///
    /// Unlike `swapBuffers`, this gives the destination the source's buffer
    /// and the source gets an unspecified (but valid) buffer. Use this when
    /// you don't need the source buffer anymore.
    ///
    /// - Parameters:
    ///   - from: Source slot (will receive destination's buffer)
    ///   - to: Destination slot (will receive source's buffer)
    public static func moveBuffer(from source: inout NetmapSlot, to dest: inout NetmapSlot) {
        dest.bufferIndex = source.bufferIndex
        dest.length = source.length
        dest.markBufferChanged()
        // Source keeps its (now dest's) buffer, but we mark it changed
        source.markBufferChanged()
    }

    // MARK: - Batch Operations

    /// Forwards packets from source to destination ring using zero-copy.
    ///
    /// This is the main high-performance forwarding function. It swaps
    /// buffer indices between corresponding slots in the two rings.
    ///
    /// - Parameters:
    ///   - source: Source RX ring
    ///   - destination: Destination TX ring
    ///   - maxPackets: Maximum packets to forward (0 = unlimited)
    /// - Returns: Number of packets forwarded
    @discardableResult
    public static func forward(
        from source: borrowing NetmapRing,
        to destination: borrowing NetmapRing,
        maxPackets: Int = 0
    ) -> Int {
        var count = 0
        let limit = maxPackets > 0 ? maxPackets : Int.max

        while !source.isEmpty && destination.hasSpace && count < limit {
            var rxSlot = source.currentSlot
            var txSlot = destination.currentSlot

            swapBuffers(&rxSlot, &txSlot)

            source.advance()
            destination.advance()
            count += 1
        }

        return count
    }

    /// Forwards packets with a filter function.
    ///
    /// Only packets where the filter returns true are forwarded.
    /// Filtered packets are still advanced in the source ring.
    ///
    /// - Parameters:
    ///   - source: Source RX ring
    ///   - destination: Destination TX ring
    ///   - filter: Predicate that receives packet data and returns true to forward
    /// - Returns: Tuple of (forwarded count, filtered count)
    public static func forwardFiltered(
        from source: borrowing NetmapRing,
        to destination: borrowing NetmapRing,
        filter: (Data) -> Bool
    ) -> (forwarded: Int, filtered: Int) {
        var forwarded = 0
        var filtered = 0

        while !source.isEmpty {
            let rxSlot = source.currentSlot
            let data = source.bufferData(for: rxSlot)

            if filter(data) && destination.hasSpace {
                var rxSlotMut = source.currentSlot
                var txSlot = destination.currentSlot
                swapBuffers(&rxSlotMut, &txSlot)
                destination.advance()
                forwarded += 1
            } else {
                filtered += 1
            }

            source.advance()
        }

        return (forwarded, filtered)
    }

    // MARK: - Multi-Ring Operations

    /// Forward result for batch operations.
    public struct ForwardResult: Sendable {
        /// Total packets forwarded.
        public let forwarded: Int

        /// Packets dropped due to no TX space.
        public let dropped: Int

        /// Source ring processed.
        public let sourceRing: UInt32

        /// Destination ring used.
        public let destinationRing: UInt32
    }

    /// Forwards packets from all source rings to corresponding destination rings.
    ///
    /// This handles multiple ring pairs, matching source ring N to destination ring N.
    /// If there are more source rings than destination rings, they wrap around.
    ///
    /// - Parameters:
    ///   - source: Source port
    ///   - destination: Destination port
    /// - Returns: Array of forward results per ring pair
    public static func forwardAll(
        from source: borrowing NetmapPort,
        to destination: borrowing NetmapPort
    ) -> [ForwardResult] {
        var results: [ForwardResult] = []
        let dstRingCount = destination.txRingCount

        for srcIdx in 0..<source.rxRingCount {
            let dstIdx = srcIdx % dstRingCount
            let srcRing = source.rxRing(srcIdx)
            let dstRing = destination.txRing(dstIdx)

            let forwarded = forward(from: srcRing, to: dstRing)
            let dropped = srcRing.isEmpty ? 0 : Int(srcRing.space)

            results.append(ForwardResult(
                forwarded: forwarded,
                dropped: dropped,
                sourceRing: srcIdx,
                destinationRing: dstIdx
            ))
        }

        return results
    }

    // MARK: - Buffer Pool Operations

    /// Checks if two ports share the same memory region.
    ///
    /// Zero-copy operations only work between ports that share memory.
    /// VALE ports and pipes typically share memory, while different
    /// physical NICs may not.
    ///
    /// - Parameters:
    ///   - port1: First port
    ///   - port2: Second port
    /// - Returns: true if the ports share memory
    public static func sharesMemory(
        _ port1: borrowing NetmapPort,
        _ port2: borrowing NetmapPort
    ) -> Bool {
        // For VALE ports on the same switch, they share memory
        // This is a heuristic - proper check requires comparing memory IDs
        // which would need additional API support
        return NetmapVALE.isVALEName(port1.interfaceName) &&
               NetmapVALE.isVALEName(port2.interfaceName)
    }
}

// MARK: - NetmapSlot Extensions

extension NetmapSlot {

    /// Copies buffer reference from another slot (zero-copy).
    ///
    /// This copies the buffer index and length, making this slot
    /// reference the same buffer as the source. Both slots are
    /// marked as changed.
    ///
    /// - Parameter other: Source slot to copy from
    public func copyBufferRef(from other: NetmapSlot) {
        self.bufferIndex = other.bufferIndex
        self.length = other.length
        self.markBufferChanged()
    }
}

// MARK: - NetmapRing Extensions

extension NetmapRing {

    /// Returns an iterator over available slots for batch processing.
    ///
    /// - Returns: Sequence of slot indices from head to tail
    public func availableSlotIndices() -> [UInt32] {
        var indices: [UInt32] = []
        var current = head
        while current != tail {
            indices.append(current)
            current = next(current)
        }
        return indices
    }

    /// Counts available slots without iteration.
    public var availableSlotCount: Int {
        return Int(space)
    }
}
