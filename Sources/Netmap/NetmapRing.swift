/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation

/// The type of a netmap ring.
public enum NetmapRingKind: UInt16, Sendable {
    case tx = 0
    case rx = 1
}

/// A view into a netmap ring buffer.
///
/// `NetmapRing` provides access to packet buffers in a netmap TX or RX ring.
/// Rings are circular buffers with head, cur, and tail pointers:
///
/// ## TX Ring Semantics
/// - `head`: First slot available for transmission
/// - `cur`: Wakeup point for poll/select
/// - `tail`: First slot reserved by kernel (read-only)
/// - Slots in range [head, tail) can be filled with packets to transmit
///
/// ## RX Ring Semantics
/// - `head`: First valid received packet
/// - `cur`: Wakeup point for poll/select
/// - `tail`: First slot reserved by kernel (read-only)
/// - Slots in range [head, tail) contain received packets
///
/// ## Example
///
/// ```swift
/// // Receive packets
/// let rxRing = port.rxRing(0)
/// while !rxRing.isEmpty {
///     let slot = rxRing.currentSlot
///     let data = rxRing.bufferData(for: slot)
///     print("Received \(slot.length) bytes")
///     rxRing.advance()
/// }
///
/// // Transmit packets
/// var txRing = port.txRing(0)
/// if txRing.hasSpace {
///     var slot = txRing.currentSlot
///     txRing.setBuffer(for: &slot, data: packetData)
///     txRing.advance()
/// }
/// ```
public struct NetmapRing: ~Copyable {
    /// Opaque pointer to the underlying netmap_ring structure.
    /// We use UnsafeMutableRawPointer because netmap_ring is over-aligned and
    /// cannot be directly used as a Swift type.
    private let ringPtr: UnsafeMutableRawPointer

    /// The kind of ring (TX or RX).
    public let kind: NetmapRingKind

    /// Ring ID within the interface.
    public var ringId: UInt16 {
        return cnm_ring_id(ringPtr)
    }

    /// Number of slots in this ring.
    public var numSlots: UInt32 {
        return cnm_ring_num_slots(ringPtr)
    }

    /// Size of each buffer in bytes.
    public var bufferSize: UInt32 {
        return cnm_ring_buf_size(ringPtr)
    }

    /// First user-owned slot (application writes here for TX, reads here for RX).
    public var head: UInt32 {
        get { cnm_ring_head(ringPtr) }
        nonmutating set { cnm_ring_set_head(ringPtr, newValue) }
    }

    /// Wakeup point - poll/select unblocks when tail moves past cur.
    public var cur: UInt32 {
        get { cnm_ring_cur(ringPtr) }
        nonmutating set { cnm_ring_set_cur(ringPtr, newValue) }
    }

    /// First kernel-owned slot (read-only).
    public var tail: UInt32 {
        return cnm_ring_tail(ringPtr)
    }

    /// Ring flags.
    public var flags: NetmapRingFlags {
        get { NetmapRingFlags(rawValue: cnm_ring_flags(ringPtr)) }
        nonmutating set { cnm_ring_set_flags(ringPtr, newValue.rawValue) }
    }

    /// Timestamp of last sync (seconds component).
    public var timestampSeconds: Int {
        return Int(cnm_ring_ts_sec(ringPtr))
    }

    /// Timestamp of last sync (microseconds component).
    public var timestampMicroseconds: Int {
        return Int(cnm_ring_ts_usec(ringPtr))
    }

    /// True if the ring is empty (no packets to process or no space available).
    public var isEmpty: Bool {
        return cnm_ring_empty(ringPtr) != 0
    }

    /// True if the ring has space (for TX) or packets (for RX).
    public var hasSpace: Bool {
        return !isEmpty
    }

    /// Number of available slots.
    public var space: UInt32 {
        return cnm_ring_space(ringPtr)
    }

    /// True if there are pending transmissions (TX ring only).
    public var hasPendingTransmissions: Bool {
        return cnm_tx_pending(ringPtr) != 0
    }

    // MARK: - Initialization

    /// Creates a ring view from a raw pointer.
    init(ringPtr: UnsafeMutableRawPointer, kind: NetmapRingKind) {
        self.ringPtr = ringPtr
        self.kind = kind
    }

    // MARK: - Slot Access

    /// Gets the next slot index (with wraparound).
    public func next(_ index: UInt32) -> UInt32 {
        return cnm_ring_next(ringPtr, index)
    }

    /// Gets the slot at the given index.
    ///
    /// - Parameter index: Slot index (0 to numSlots-1)
    /// - Returns: The slot at that index
    /// - Precondition: index < numSlots
    public func slot(at index: UInt32) -> NetmapSlot {
        precondition(index < numSlots, "Slot index out of bounds")
        let slotPtr = cnm_ring_slot(ringPtr, index)!
        return NetmapSlot(slot: slotPtr, ringPtr: ringPtr)
    }

    /// Gets the slot at the current head position.
    public var currentSlot: NetmapSlot {
        return slot(at: head)
    }

    // MARK: - Buffer Access

    /// Gets a pointer to the buffer for a slot.
    ///
    /// - Parameter slot: The slot
    /// - Returns: Pointer to the buffer data
    public func buffer(for slot: NetmapSlot) -> UnsafeMutablePointer<UInt8> {
        let buf = cnm_buf(ringPtr, slot.bufferIndex)!
        return buf.withMemoryRebound(to: UInt8.self, capacity: Int(bufferSize)) { $0 }
    }

    /// Gets the buffer data for a slot as Data.
    ///
    /// - Parameter slot: The slot
    /// - Returns: The packet data (length determined by slot.length)
    public func bufferData(for slot: NetmapSlot) -> Data {
        let buf = buffer(for: slot)
        return Data(bytes: buf, count: Int(slot.length))
    }

    /// Sets the buffer data for a slot.
    ///
    /// - Parameters:
    ///   - slot: The slot to modify
    ///   - data: The packet data to copy
    /// - Precondition: data.count <= bufferSize
    public func setBuffer(for slot: inout NetmapSlot, data: Data) {
        precondition(data.count <= Int(bufferSize), "Data exceeds buffer size")
        let buf = buffer(for: slot)
        data.withUnsafeBytes { srcPtr in
            _ = memcpy(buf, srcPtr.baseAddress, data.count)
        }
        slot.length = UInt16(data.count)
    }

    /// Sets the buffer data using an optimized copy.
    ///
    /// - Parameters:
    ///   - slot: The slot to modify
    ///   - source: Source buffer pointer
    ///   - length: Number of bytes to copy
    public func setBuffer(for slot: inout NetmapSlot, source: UnsafeRawPointer, length: Int) {
        precondition(length <= Int(bufferSize), "Length exceeds buffer size")
        let buf = buffer(for: slot)
        cnm_pkt_copy(source, buf, Int32(length))
        slot.length = UInt16(length)
    }

    // MARK: - Ring Iteration

    /// Advances head to the next slot.
    ///
    /// Call this after processing a slot to release it back to the kernel (RX)
    /// or to queue it for transmission (TX).
    public func advance() {
        head = next(head)
        cur = head
    }

    /// Advances head by multiple slots.
    ///
    /// - Parameter count: Number of slots to advance
    public func advance(by count: Int) {
        var h = head
        for _ in 0..<count {
            h = next(h)
        }
        head = h
        cur = h
    }

    // MARK: - Iteration Helpers

    /// Calls the given closure for each available slot.
    ///
    /// For RX rings, this iterates over received packets.
    /// For TX rings, this iterates over available transmission slots.
    ///
    /// - Parameter body: A closure that takes a slot index
    public func forEach(_ body: (UInt32) throws -> Void) rethrows {
        var current = head
        let end = tail
        while current != end {
            try body(current)
            current = next(current)
        }
    }

    /// Calls the given closure for each available slot, with the slot.
    ///
    /// - Parameter body: A closure that takes a NetmapSlot
    public func forEachSlot(_ body: (NetmapSlot) throws -> Void) rethrows {
        var current = head
        let end = tail
        while current != end {
            let slotPtr = cnm_ring_slot(ringPtr, current)!
            let slot = NetmapSlot(slot: slotPtr, ringPtr: ringPtr)
            try body(slot)
            current = next(current)
        }
    }

    // MARK: - Extra Buffers Support

    /// Gets the next buffer index from an extra buffer.
    ///
    /// Extra buffers form a linked list where the first uint32_t of each
    /// buffer contains the index of the next buffer (0 = end of list).
    ///
    /// - Parameter bufferIndex: The current buffer index
    /// - Returns: The next buffer index in the list (0 = end)
    public func getNextExtraBuffer(_ bufferIndex: UInt32) -> UInt32 {
        return cnm_extra_buf_next(ringPtr, bufferIndex)
    }

    /// Sets the next buffer index in an extra buffer.
    ///
    /// - Parameters:
    ///   - bufferIndex: The buffer to modify
    ///   - next: The next buffer index (0 = end of list)
    public func setNextExtraBuffer(_ bufferIndex: UInt32, next: UInt32) {
        cnm_extra_buf_set_next(ringPtr, bufferIndex, next)
    }

    /// Gets a raw pointer to a buffer by index.
    ///
    /// This is useful for extra buffer manipulation or advanced zero-copy
    /// operations where you need direct buffer access.
    ///
    /// - Parameter bufferIndex: The buffer index
    /// - Returns: Pointer to the buffer
    public func bufferPointer(at bufferIndex: UInt32) -> UnsafeMutablePointer<UInt8> {
        let buf = cnm_buf(ringPtr, bufferIndex)!
        return buf.withMemoryRebound(to: UInt8.self, capacity: Int(bufferSize)) { $0 }
    }
}
