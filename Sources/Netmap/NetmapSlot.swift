/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap

/// A slot in a netmap ring.
///
/// Each slot in a netmap ring describes a buffer that can hold a packet.
/// Slots contain:
/// - `bufferIndex`: Index of the buffer in the shared memory region
/// - `length`: Length of the packet data in the buffer
/// - `flags`: Control flags for the slot
/// - `ptr`: Pointer field (used for indirect buffers or offsets)
///
/// ## TX Ring Slots
///
/// When transmitting, fill the buffer, set the length, and advance the ring head:
///
/// ```swift
/// var slot = txRing.currentSlot
/// txRing.setBuffer(for: &slot, data: packetData)
/// txRing.advance()
/// try port.txSync()
/// ```
///
/// ## RX Ring Slots
///
/// When receiving, read the packet data and advance the ring head:
///
/// ```swift
/// let slot = rxRing.currentSlot
/// let packet = rxRing.bufferData(for: slot)
/// // Process packet...
/// rxRing.advance()
/// ```
///
/// ## Buffer Swapping
///
/// For zero-copy forwarding, you can swap buffer indices between slots:
///
/// ```swift
/// var rxSlot = rxRing.currentSlot
/// var txSlot = txRing.currentSlot
///
/// // Swap buffers (zero-copy)
/// let rxBuf = rxSlot.bufferIndex
/// rxSlot.bufferIndex = txSlot.bufferIndex
/// txSlot.bufferIndex = rxBuf
///
/// // Mark as changed
/// rxSlot.flags.insert(.bufferChanged)
/// txSlot.flags.insert(.bufferChanged)
///
/// txSlot.length = rxSlot.length
/// ```
public struct NetmapSlot {
    /// Pointer to the underlying netmap_slot structure.
    private let slot: UnsafeMutablePointer<netmap_slot>

    /// Raw pointer to the owning ring (for offset calculations).
    private let ringPtr: UnsafeMutableRawPointer

    /// Buffer index in the shared memory region.
    public var bufferIndex: UInt32 {
        get { slot.pointee.buf_idx }
        nonmutating set { slot.pointee.buf_idx = newValue }
    }

    /// Length of packet data in the buffer.
    public var length: UInt16 {
        get { slot.pointee.len }
        nonmutating set { slot.pointee.len = newValue }
    }

    /// Slot flags.
    public var flags: NetmapSlotFlags {
        get { NetmapSlotFlags(rawValue: slot.pointee.flags) }
        nonmutating set { slot.pointee.flags = newValue.rawValue }
    }

    /// Pointer field (for indirect buffers or offset storage).
    public var ptr: UInt64 {
        get { slot.pointee.ptr }
        nonmutating set { slot.pointee.ptr = newValue }
    }

    /// True if this slot has more fragments following.
    public var hasMoreFragments: Bool {
        return flags.contains(.moreFragments)
    }

    /// Number of fragments (for RX VALE ring slots).
    public var fragmentCount: UInt8 {
        return UInt8((slot.pointee.flags >> 8) & 0xFF)
    }

    // MARK: - Initialization

    /// Creates a slot view from raw pointers.
    init(slot: UnsafeMutablePointer<netmap_slot>, ringPtr: UnsafeMutableRawPointer) {
        self.slot = slot
        self.ringPtr = ringPtr
    }

    // MARK: - Buffer Offset Operations

    /// Gets the offset field from the ptr.
    public var offset: UInt64 {
        return cnm_roffset(ringPtr, slot)
    }

    /// Sets the offset field in the ptr.
    public func setOffset(_ offset: UInt64) {
        cnm_woffset(ringPtr, slot, offset)
    }

    // MARK: - Convenience Methods

    /// Clears the slot for reuse.
    ///
    /// Resets length and flags to zero. Does not change buffer index.
    public func clear() {
        length = 0
        flags = []
    }

    /// Prepares the slot for transmission.
    ///
    /// - Parameter length: The packet length
    /// - Parameter report: Whether to request completion notification
    public func prepareForTx(length: UInt16, report: Bool = false) {
        self.length = length
        if report {
            flags = .report
        } else {
            flags = []
        }
    }

    /// Marks the buffer index as changed.
    ///
    /// Call this after swapping buffer indices between slots.
    public func markBufferChanged() {
        flags.insert(.bufferChanged)
    }
}

// MARK: - CustomStringConvertible

extension NetmapSlot: CustomStringConvertible {
    public var description: String {
        return "NetmapSlot(buf=\(bufferIndex), len=\(length), flags=\(flags.rawValue))"
    }
}
