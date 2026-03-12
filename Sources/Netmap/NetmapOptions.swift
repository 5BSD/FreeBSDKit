/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation
import Glibc

// MARK: - External Memory Option

/// Configuration for external memory (hugepages) support.
///
/// External memory allows netmap to use pre-allocated memory regions,
/// such as hugepages, for better performance and NUMA locality.
///
/// ## Example
///
/// ```swift
/// // Allocate 2MB hugepage
/// let size = 2 * 1024 * 1024
/// let mem = mmap(nil, size, PROT_READ | PROT_WRITE,
///                MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0)
///
/// let config = NetmapExternalMemory(
///     memory: mem!,
///     bufferCount: 512,
///     bufferSize: 2048
/// )
///
/// let port = try NetmapPort.open(
///     interface: "vale0:hugepage",
///     options: .externalMemory(config)
/// )
/// ```
///
/// ## Thread Safety
///
/// This type is marked `@unchecked Sendable` because it contains a raw pointer.
/// The pointer is only used during port registration and is not accessed after
/// the port is opened. The user is responsible for ensuring the memory remains
/// valid for the lifetime of the port.
public struct NetmapExternalMemory: @unchecked Sendable {
    /// Pointer to user-allocated memory region.
    public let memory: UnsafeMutableRawPointer

    /// Memory allocator ID (0 for new allocation).
    public let memoryId: UInt16

    /// Number of interface objects.
    public let interfaceCount: UInt32

    /// Size of each interface object.
    public let interfaceSize: UInt32

    /// Number of ring objects.
    public let ringCount: UInt32

    /// Size of each ring object.
    public let ringSize: UInt32

    /// Number of buffer objects.
    public let bufferCount: UInt32

    /// Size of each buffer.
    public let bufferSize: UInt32

    /// Creates an external memory configuration.
    ///
    /// - Parameters:
    ///   - memory: Pointer to pre-allocated memory (e.g., hugepage)
    ///   - memoryId: Memory allocator ID (0 for new)
    ///   - interfaceCount: Number of interface objects (default 1)
    ///   - interfaceSize: Size of interface objects (default 1024)
    ///   - ringCount: Number of ring objects (default 16)
    ///   - ringSize: Size of ring objects (default 16384)
    ///   - bufferCount: Number of packet buffers
    ///   - bufferSize: Size of each buffer (default 2048)
    public init(
        memory: UnsafeMutableRawPointer,
        memoryId: UInt16 = 0,
        interfaceCount: UInt32 = 1,
        interfaceSize: UInt32 = 1024,
        ringCount: UInt32 = 16,
        ringSize: UInt32 = 16384,
        bufferCount: UInt32,
        bufferSize: UInt32 = 2048
    ) {
        self.memory = memory
        self.memoryId = memoryId
        self.interfaceCount = interfaceCount
        self.interfaceSize = interfaceSize
        self.ringCount = ringCount
        self.ringSize = ringSize
        self.bufferCount = bufferCount
        self.bufferSize = bufferSize
    }
}

// MARK: - Packet Offset Option

/// Configuration for packet offset support.
///
/// Packet offsets allow storing the packet start position within a buffer,
/// useful for adding header room or handling hardware offsets.
///
/// The offset is stored in the `ptr` field of the slot structure.
public struct NetmapPacketOffsets: Sendable {
    /// Maximum offset value that will be used.
    public let maxOffset: UInt64

    /// Initial offset to set in all slots.
    public let initialOffset: UInt64

    /// Number of bits used for the offset field.
    public let bits: UInt32

    /// Creates a packet offset configuration.
    ///
    /// - Parameters:
    ///   - maxOffset: Maximum offset value (will be validated/adjusted by kernel)
    ///   - initialOffset: Initial offset for all slots
    ///   - bits: Number of bits for offset field (0 for default)
    public init(maxOffset: UInt64, initialOffset: UInt64 = 0, bits: UInt32 = 0) {
        self.maxOffset = maxOffset
        self.initialOffset = initialOffset
        self.bits = bits
    }

    /// Creates offset configuration for header room.
    ///
    /// - Parameter headerRoom: Number of bytes to reserve at buffer start
    /// - Returns: Configured offsets
    public static func headerRoom(_ headerRoom: UInt64) -> NetmapPacketOffsets {
        return NetmapPacketOffsets(maxOffset: headerRoom, initialOffset: headerRoom)
    }
}

// MARK: - Kloop Eventfd Option

/// Configuration for kloop eventfd notifications.
///
/// Eventfds provide efficient notifications between the kernel sync loop
/// and the application, useful for VM networking where the hypervisor
/// uses eventfds for interrupt injection.
public struct NetmapKloopEventfds: @unchecked Sendable {
    /// Ring eventfd entries.
    public struct RingEntry: Sendable {
        /// Eventfd for I/O events (application -> kernel).
        public let ioeventfd: Int32

        /// Eventfd for IRQ events (kernel -> application).
        public let irqfd: Int32

        /// Creates a ring entry.
        public init(ioeventfd: Int32, irqfd: Int32) {
            self.ioeventfd = ioeventfd
            self.irqfd = irqfd
        }

        /// Disabled entry (no eventfd).
        public static let disabled = RingEntry(ioeventfd: -1, irqfd: -1)
    }

    /// Entries for each ring.
    public let entries: [RingEntry]

    /// Creates eventfd configuration.
    ///
    /// - Parameter entries: One entry per ring (TX rings first, then RX rings)
    public init(entries: [RingEntry]) {
        self.entries = entries
    }
}

// MARK: - Kloop Mode Option

/// Mode flags for kernel sync loop.
public struct NetmapKloopMode: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Sync TX rings directly in VM exit context.
    public static let directTX = NetmapKloopMode(rawValue: UInt32(CNM_KLOOP_DIRECT_TX))

    /// Sync RX rings directly in VM exit context.
    public static let directRX = NetmapKloopMode(rawValue: UInt32(CNM_KLOOP_DIRECT_RX))

    /// Sync both TX and RX directly.
    public static let directBoth: NetmapKloopMode = [.directTX, .directRX]
}

// MARK: - CSB Configuration

/// Control/Status Block configuration for VM networking.
///
/// CSB mode provides an alternative synchronization mechanism where
/// ring head/cur/tail pointers are exchanged through a shared memory
/// area instead of the ring structure. This reduces VM exits.
///
/// ## Memory Layout
///
/// CSB requires two arrays of entries, one per ring:
/// - `atok` (Application to Kernel): Application writes head/cur
/// - `ktoa` (Kernel to Application): Kernel writes hwcur/hwtail
///
/// ## Example
///
/// ```swift
/// let numRings = 4  // 2 TX + 2 RX
/// let csb = try NetmapCSB(ringCount: numRings)
///
/// let port = try NetmapPort.open(
///     interface: "vale0:vm",
///     options: .csb(csb)
/// )
///
/// // Use CSB for synchronization
/// csb.setHead(ring: 0, value: newHead)
/// let tail = csb.getTail(ring: 0)
/// ```
///
/// ## Thread Safety
///
/// This type is marked `@unchecked Sendable` because it manages raw memory
/// for CSB entries. The CSB arrays are allocated at initialization and freed
/// in deinit. Access to CSB entries should be synchronized externally when
/// used from multiple threads.
public final class NetmapCSB: @unchecked Sendable {
    /// Number of rings.
    public let ringCount: Int

    /// Application-to-kernel CSB entries.
    internal let atok: UnsafeMutablePointer<nm_csb_atok>

    /// Kernel-to-application CSB entries.
    internal let ktoa: UnsafeMutablePointer<nm_csb_ktoa>

    /// Creates CSB configuration.
    ///
    /// - Parameter ringCount: Total number of rings (TX + RX)
    /// - Throws: If memory allocation fails
    public init(ringCount: Int) throws {
        guard ringCount > 0 else {
            throw NetmapError.invalidConfiguration("ringCount must be > 0")
        }

        self.ringCount = ringCount

        // Allocate cache-line aligned memory
        let atokSize = ringCount * MemoryLayout<nm_csb_atok>.stride
        let ktoaSize = ringCount * MemoryLayout<nm_csb_ktoa>.stride

        guard let atokPtr = aligned_alloc(128, atokSize) else {
            throw NetmapError.allocationFailed
        }
        guard let ktoaPtr = aligned_alloc(128, ktoaSize) else {
            free(atokPtr)
            throw NetmapError.allocationFailed
        }

        self.atok = atokPtr.assumingMemoryBound(to: nm_csb_atok.self)
        self.ktoa = ktoaPtr.assumingMemoryBound(to: nm_csb_ktoa.self)

        // Zero initialize
        memset(atokPtr, 0, atokSize)
        memset(ktoaPtr, 0, ktoaSize)
    }

    deinit {
        free(atok)
        free(ktoa)
    }

    // MARK: - Application to Kernel (write head/cur)

    /// Sets the head pointer for a ring.
    public func setHead(ring: Int, value: UInt32) {
        precondition(ring >= 0 && ring < ringCount)
        cnm_csb_atok_set_head(&atok[ring], value)
    }

    /// Sets the cur pointer for a ring.
    public func setCur(ring: Int, value: UInt32) {
        precondition(ring >= 0 && ring < ringCount)
        cnm_csb_atok_set_cur(&atok[ring], value)
    }

    /// Sets whether the application needs a kick (notification).
    public func setApplNeedKick(ring: Int, value: Bool) {
        precondition(ring >= 0 && ring < ringCount)
        cnm_csb_atok_set_appl_need_kick(&atok[ring], value ? 1 : 0)
    }

    /// Sets sync flags for a ring.
    public func setSyncFlags(ring: Int, flags: UInt32) {
        precondition(ring >= 0 && ring < ringCount)
        cnm_csb_atok_set_sync_flags(&atok[ring], flags)
    }

    // MARK: - Kernel to Application (read hwcur/hwtail)

    /// Gets the hardware cur pointer for a ring.
    public func getHwcur(ring: Int) -> UInt32 {
        precondition(ring >= 0 && ring < ringCount)
        return cnm_csb_ktoa_hwcur(&ktoa[ring])
    }

    /// Gets the hardware tail pointer for a ring.
    public func getHwtail(ring: Int) -> UInt32 {
        precondition(ring >= 0 && ring < ringCount)
        return cnm_csb_ktoa_hwtail(&ktoa[ring])
    }

    /// Gets whether the kernel needs a kick.
    public func getKernNeedKick(ring: Int) -> Bool {
        precondition(ring >= 0 && ring < ringCount)
        return cnm_csb_ktoa_kern_need_kick(&ktoa[ring]) != 0
    }

    // MARK: - Convenience

    /// Gets the number of available slots for a TX ring.
    ///
    /// - Parameters:
    ///   - ring: Ring index
    ///   - numSlots: Total slots in the ring
    /// - Returns: Number of available slots
    public func txSpace(ring: Int, numSlots: UInt32) -> UInt32 {
        let head = cnm_csb_atok_head(&atok[ring])
        let tail = cnm_csb_ktoa_hwtail(&ktoa[ring])
        if tail >= head {
            return tail - head
        } else {
            return numSlots - head + tail
        }
    }

    /// Gets the number of available packets for an RX ring.
    ///
    /// - Parameters:
    ///   - ring: Ring index
    ///   - numSlots: Total slots in the ring
    /// - Returns: Number of available packets
    public func rxSpace(ring: Int, numSlots: UInt32) -> UInt32 {
        let head = cnm_csb_atok_head(&atok[ring])
        let tail = cnm_csb_ktoa_hwtail(&ktoa[ring])
        if tail >= head {
            return tail - head
        } else {
            return numSlots - head + tail
        }
    }
}

// MARK: - Netmap Options Builder

/// Options for netmap port registration.
///
/// Options are passed during `NetmapPort.open()` to configure advanced
/// features like external memory, packet offsets, or CSB mode.
///
/// ## Example
///
/// ```swift
/// // Open with packet offset support
/// let port = try NetmapPort.open(
///     interface: "em0",
///     options: .offsets(NetmapPacketOffsets.headerRoom(64))
/// )
///
/// // Open with CSB mode for VM networking
/// let csb = try NetmapCSB(ringCount: 4)
/// let port = try NetmapPort.open(
///     interface: "vale0:vm",
///     options: .csb(csb)
/// )
/// ```
///
/// ## Thread Safety
///
/// This type is marked `@unchecked Sendable` because it may contain references
/// to types with raw pointers. Options are only used during port registration
/// and are not accessed concurrently.
public struct NetmapOptions: @unchecked Sendable {
    /// External memory configuration.
    public var externalMemory: NetmapExternalMemory?

    /// Packet offset configuration.
    public var offsets: NetmapPacketOffsets?

    /// CSB configuration.
    public var csb: NetmapCSB?

    /// Kloop eventfd configuration.
    public var kloopEventfds: NetmapKloopEventfds?

    /// Kloop mode flags.
    public var kloopMode: NetmapKloopMode?

    /// Creates empty options.
    public init() {}

    /// Creates options with external memory.
    public static func externalMemory(_ config: NetmapExternalMemory) -> NetmapOptions {
        var opts = NetmapOptions()
        opts.externalMemory = config
        return opts
    }

    /// Creates options with packet offsets.
    public static func offsets(_ config: NetmapPacketOffsets) -> NetmapOptions {
        var opts = NetmapOptions()
        opts.offsets = config
        return opts
    }

    /// Creates options with CSB mode.
    public static func csb(_ config: NetmapCSB) -> NetmapOptions {
        var opts = NetmapOptions()
        opts.csb = config
        return opts
    }

    /// Creates options with kloop eventfds.
    public static func kloopEventfds(_ config: NetmapKloopEventfds) -> NetmapOptions {
        var opts = NetmapOptions()
        opts.kloopEventfds = config
        return opts
    }

    /// Creates options with kloop mode.
    public static func kloopMode(_ mode: NetmapKloopMode) -> NetmapOptions {
        var opts = NetmapOptions()
        opts.kloopMode = mode
        return opts
    }

    /// Combines multiple options.
    public func with(externalMemory config: NetmapExternalMemory) -> NetmapOptions {
        var opts = self
        opts.externalMemory = config
        return opts
    }

    /// Combines multiple options.
    public func with(offsets config: NetmapPacketOffsets) -> NetmapOptions {
        var opts = self
        opts.offsets = config
        return opts
    }

    /// Combines multiple options.
    public func with(csb config: NetmapCSB) -> NetmapOptions {
        var opts = self
        opts.csb = config
        return opts
    }

    /// Combines multiple options.
    public func with(kloopEventfds config: NetmapKloopEventfds) -> NetmapOptions {
        var opts = self
        opts.kloopEventfds = config
        return opts
    }

    /// Combines multiple options.
    public func with(kloopMode mode: NetmapKloopMode) -> NetmapOptions {
        var opts = self
        opts.kloopMode = mode
        return opts
    }

    /// Returns true if any options are set.
    public var hasOptions: Bool {
        return externalMemory != nil ||
               offsets != nil ||
               csb != nil ||
               kloopEventfds != nil ||
               kloopMode != nil
    }
}

// MARK: - Internal Option Building

extension NetmapOptions {
    /// Storage for option structures during registration.
    internal final class OptionStorage {
        var extmem: nmreq_opt_extmem?
        var offsets: nmreq_opt_offsets?
        var csb: nmreq_opt_csb?
        var kloopMode: nmreq_opt_sync_kloop_mode?
        var kloopEventfdsData: UnsafeMutableRawPointer?
        var kloopEventfdsSize: Int = 0

        deinit {
            if let ptr = kloopEventfdsData {
                free(ptr)
            }
        }
    }

    /// Builds the option chain and returns storage that must be kept alive.
    internal func buildOptionChain(header: inout nmreq_header) -> OptionStorage {
        let storage = OptionStorage()

        // External memory option
        if let extmem = externalMemory {
            storage.extmem = nmreq_opt_extmem()
            cnm_init_opt_extmem(
                &storage.extmem!,
                extmem.memory,
                extmem.memoryId,
                extmem.interfaceCount,
                extmem.interfaceSize,
                extmem.ringCount,
                extmem.ringSize,
                extmem.bufferCount,
                extmem.bufferSize
            )
            withUnsafeMutablePointer(to: &storage.extmem!.nro_opt) { optPtr in
                cnm_header_add_option(&header, optPtr)
            }
        }

        // Offsets option
        if let offsets = offsets {
            storage.offsets = nmreq_opt_offsets()
            cnm_init_opt_offsets(
                &storage.offsets!,
                offsets.maxOffset,
                offsets.initialOffset,
                offsets.bits
            )
            withUnsafeMutablePointer(to: &storage.offsets!.nro_opt) { optPtr in
                cnm_header_add_option(&header, optPtr)
            }
        }

        // CSB option
        if let csb = csb {
            storage.csb = nmreq_opt_csb()
            cnm_init_opt_csb(&storage.csb!, csb.atok, csb.ktoa)
            withUnsafeMutablePointer(to: &storage.csb!.nro_opt) { optPtr in
                cnm_header_add_option(&header, optPtr)
            }
        }

        // Kloop eventfds option
        if let eventfds = kloopEventfds {
            let numEntries = UInt32(eventfds.entries.count)
            let size = cnm_opt_sync_kloop_eventfds_size(numEntries)
            storage.kloopEventfdsData = malloc(size)
            storage.kloopEventfdsSize = size

            if let ptr = storage.kloopEventfdsData {
                let evfdsPtr = ptr.assumingMemoryBound(to: nmreq_opt_sync_kloop_eventfds.self)
                cnm_init_opt_sync_kloop_eventfds(evfdsPtr, numEntries)

                for (idx, entry) in eventfds.entries.enumerated() {
                    cnm_opt_sync_kloop_set_eventfd(
                        evfdsPtr,
                        UInt32(idx),
                        entry.ioeventfd,
                        entry.irqfd
                    )
                }

                cnm_header_add_option(&header, &evfdsPtr.pointee.nro_opt)
            }
        }

        // Kloop mode option
        if let mode = kloopMode {
            storage.kloopMode = nmreq_opt_sync_kloop_mode()
            cnm_init_opt_sync_kloop_mode(&storage.kloopMode!, mode.rawValue)
            withUnsafeMutablePointer(to: &storage.kloopMode!.nro_opt) { optPtr in
                cnm_header_add_option(&header, optPtr)
            }
        }

        return storage
    }
}
