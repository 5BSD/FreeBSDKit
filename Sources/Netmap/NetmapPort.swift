/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation
import Glibc

/// The netmap device path.
private let netmapDevicePath = "/dev/netmap"

/// A netmap port providing high-performance packet I/O.
///
/// `NetmapPort` is a move-only type that manages the lifecycle of a netmap
/// file descriptor and its associated memory-mapped region. It provides
/// direct access to NIC ring buffers, bypassing the kernel network stack
/// for maximum performance.
///
/// ## Basic Usage
///
/// ```swift
/// // Open a netmap port on interface em0
/// var port = try NetmapPort.open(interface: "em0")
///
/// // Receive packets
/// let rxRing = port.rxRing(0)
/// while !rxRing.isEmpty {
///     let slot = rxRing.currentSlot
///     let packet = rxRing.bufferData(for: slot)
///     // Process packet...
///     rxRing.advance()
/// }
/// try port.rxSync()
///
/// // Transmit packets
/// let txRing = port.txRing(0)
/// if txRing.hasSpace {
///     var slot = txRing.currentSlot
///     txRing.setBuffer(for: &slot, data: packetData)
///     txRing.advance()
///     try port.txSync()
/// }
/// ```
///
/// ## Port Types
///
/// - **NIC mode**: Direct access to physical NIC rings
/// - **Host mode**: Intercept packets to/from host stack
/// - **VALE switch**: Software L2 switch port
/// - **Pipe mode**: Zero-copy IPC channel
///
/// ## Thread Safety
///
/// `NetmapPort` is not thread-safe. Each thread should have its own port,
/// or access should be synchronized externally.
public struct NetmapPort: ~Copyable {
    /// The file descriptor for /dev/netmap.
    private var fd: Int32

    /// The memory-mapped region base address.
    private var memBase: UnsafeMutableRawPointer?

    /// The size of the memory-mapped region.
    private var memSize: Int

    /// Whether we own the memory mapping (false for external memory).
    private var ownsMemory: Bool

    /// Raw pointer to the netmap_if structure.
    private var nifpPtr: UnsafeMutableRawPointer?

    /// Registration info from the kernel.
    private var regInfo: nmreq_register

    /// The interface name.
    public let interfaceName: String

    /// Number of TX rings.
    public var txRingCount: UInt32 {
        guard let nifp = nifpPtr else { return 0 }
        return cnm_if_tx_rings(nifp)
    }

    /// Number of RX rings.
    public var rxRingCount: UInt32 {
        guard let nifp = nifpPtr else { return 0 }
        return cnm_if_rx_rings(nifp)
    }

    /// Number of host TX rings.
    public var hostTxRingCount: UInt32 {
        guard let nifp = nifpPtr else { return 0 }
        return cnm_if_host_tx_rings(nifp)
    }

    /// Number of host RX rings.
    public var hostRxRingCount: UInt32 {
        guard let nifp = nifpPtr else { return 0 }
        return cnm_if_host_rx_rings(nifp)
    }

    /// Whether the port is currently registered.
    public var isRegistered: Bool {
        return nifpPtr != nil
    }

    /// Number of extra buffers allocated.
    ///
    /// This may be less than requested if there wasn't enough memory.
    public var extraBufferCount: UInt32 {
        var info = regInfo
        return cnm_register_get_extra_bufs(&info)
    }

    /// The raw file descriptor (for use with poll/kqueue).
    public var fileDescriptor: Int32 {
        return fd
    }

    // MARK: - Initialization

    /// Opens a netmap port for the specified interface.
    ///
    /// - Parameters:
    ///   - interface: The interface name (e.g., "em0", "vale0:port1")
    ///   - mode: The registration mode (default: all NIC rings)
    ///   - flags: Additional registration flags
    ///   - ringId: Ring ID for single-ring modes
    ///   - extraBuffers: Number of extra buffers to request (0 for default)
    /// - Throws: `NetmapError` if opening or registration fails
    public static func open(
        interface: String,
        mode: NetmapRegistrationMode = .allNIC,
        flags: NetmapRegistrationFlags = [],
        ringId: UInt16 = 0,
        extraBuffers: UInt32 = 0
    ) throws -> NetmapPort {
        return try open(
            interface: interface,
            mode: mode,
            flags: flags,
            ringId: ringId,
            extraBuffers: extraBuffers,
            options: nil
        )
    }

    /// Opens a netmap port with advanced options.
    ///
    /// - Parameters:
    ///   - interface: The interface name (e.g., "em0", "vale0:port1")
    ///   - mode: The registration mode (default: all NIC rings)
    ///   - flags: Additional registration flags
    ///   - ringId: Ring ID for single-ring modes
    ///   - extraBuffers: Number of extra buffers to request (0 for default)
    ///   - options: Advanced options (external memory, offsets, CSB, etc.)
    /// - Throws: `NetmapError` if opening or registration fails
    ///
    /// ## Example with External Memory
    ///
    /// ```swift
    /// let extmem = NetmapExternalMemory(
    ///     memory: hugepagePtr,
    ///     bufferCount: 512,
    ///     bufferSize: 2048
    /// )
    /// let port = try NetmapPort.open(
    ///     interface: "vale0:ext",
    ///     options: .externalMemory(extmem)
    /// )
    /// ```
    ///
    /// ## Example with Packet Offsets
    ///
    /// ```swift
    /// let port = try NetmapPort.open(
    ///     interface: "em0",
    ///     options: .offsets(NetmapPacketOffsets.headerRoom(64))
    /// )
    /// ```
    ///
    /// ## Example with CSB Mode
    ///
    /// ```swift
    /// let csb = try NetmapCSB(ringCount: 4)
    /// let port = try NetmapPort.open(
    ///     interface: "vale0:vm",
    ///     options: .csb(csb)
    /// )
    /// ```
    public static func open(
        interface: String,
        mode: NetmapRegistrationMode = .allNIC,
        flags: NetmapRegistrationFlags = [],
        ringId: UInt16 = 0,
        extraBuffers: UInt32 = 0,
        options: NetmapOptions?
    ) throws -> NetmapPort {
        // Validate interface name
        guard interface.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(interface)
        }

        // Open /dev/netmap
        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }

        // Create port and register
        var port = NetmapPort(fd: fd, interfaceName: interface)
        try port.register(
            mode: mode,
            flags: flags,
            ringId: ringId,
            extraBuffers: extraBuffers,
            options: options
        )

        return port
    }

    /// Private initializer.
    private init(fd: Int32, interfaceName: String) {
        self.fd = fd
        self.interfaceName = interfaceName
        self.memBase = nil
        self.memSize = 0
        self.ownsMemory = true
        self.nifpPtr = nil
        self.regInfo = nmreq_register()
    }

    deinit {
        if let mem = memBase, ownsMemory {
            _ = cnm_munmap(mem, memSize)
        }
        if fd >= 0 {
            Glibc.close(fd)
        }
    }

    // MARK: - Registration

    /// Registers the port with the kernel.
    private mutating func register(
        mode: NetmapRegistrationMode,
        flags: NetmapRegistrationFlags,
        ringId: UInt16,
        extraBuffers: UInt32 = 0,
        options: NetmapOptions? = nil
    ) throws {
        // Prepare registration request
        var reg = nmreq_register()
        cnm_init_register(&reg, mode.rawValue, flags.rawValue)
        reg.nr_ringid = ringId
        if extraBuffers > 0 {
            cnm_register_set_extra_bufs(&reg, extraBuffers)
        }

        // Prepare header
        var hdr = nmreq_header()
        cnm_init_header(&hdr, interfaceName, UInt16(CNM_REQ_REGISTER), &reg)

        // Build option chain if options provided
        // Note: optionStorage must stay alive until after the ioctl
        var optionStorage: NetmapOptions.OptionStorage?
        if let options = options, options.hasOptions {
            optionStorage = options.buildOptionChain(header: &hdr)
        }

        // Perform registration
        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }

        // Check option status if any were provided
        if let storage = optionStorage {
            // Check each option's status
            if storage.extmem != nil {
                var opt = storage.extmem!.nro_opt
                if cnm_option_status(&opt) != 0 {
                    throw NetmapError.optionRejected(
                        option: "EXTMEM",
                        errno: Int32(cnm_option_status(&opt))
                    )
                }
            }
            if storage.offsets != nil {
                var opt = storage.offsets!.nro_opt
                if cnm_option_status(&opt) != 0 {
                    throw NetmapError.optionRejected(
                        option: "OFFSETS",
                        errno: Int32(cnm_option_status(&opt))
                    )
                }
            }
            if storage.csb != nil {
                var opt = storage.csb!.nro_opt
                if cnm_option_status(&opt) != 0 {
                    throw NetmapError.optionRejected(
                        option: "CSB",
                        errno: Int32(cnm_option_status(&opt))
                    )
                }
            }
            if storage.kloopMode != nil {
                var opt = storage.kloopMode!.nro_opt
                if cnm_option_status(&opt) != 0 {
                    throw NetmapError.optionRejected(
                        option: "SYNC_KLOOP_MODE",
                        errno: Int32(cnm_option_status(&opt))
                    )
                }
            }
        }

        // Memory map the region (unless using external memory)
        let size = Int(reg.nr_memsize)
        if options?.externalMemory == nil {
            let mem = cnm_mmap(fd, size)
            guard cnm_mmap_failed(mem) == 0, let validMem = mem else {
                throw NetmapError.mmapFailed(errno: errno)
            }
            self.memBase = validMem
            self.ownsMemory = true
        } else {
            // External memory was provided, use it directly
            // We don't own this memory, so don't munmap it in deinit
            self.memBase = options!.externalMemory!.memory
            self.ownsMemory = false
        }
        self.memSize = size
        self.nifpPtr = cnm_if(memBase, reg.nr_offset)
        self.regInfo = reg
    }

    // MARK: - Ring Access

    /// Gets a TX ring by index.
    ///
    /// - Parameter index: The ring index (0 to txRingCount-1)
    /// - Returns: A borrowed reference to the TX ring
    /// - Precondition: index < txRingCount
    public borrowing func txRing(_ index: UInt32) -> NetmapRing {
        precondition(index < txRingCount, "TX ring index out of bounds")
        let ring = cnm_txring(nifpPtr, index)!
        return NetmapRing(ringPtr: ring, kind: .tx)
    }

    /// Gets an RX ring by index.
    ///
    /// - Parameter index: The ring index (0 to rxRingCount-1)
    /// - Returns: A borrowed reference to the RX ring
    /// - Precondition: index < rxRingCount
    public borrowing func rxRing(_ index: UInt32) -> NetmapRing {
        precondition(index < rxRingCount, "RX ring index out of bounds")
        let ring = cnm_rxring(nifpPtr, index)!
        return NetmapRing(ringPtr: ring, kind: .rx)
    }

    /// Iterates over all TX rings.
    public borrowing func forEachTxRing(_ body: (borrowing NetmapRing) throws -> Void) rethrows {
        for i in 0..<txRingCount {
            try body(txRing(i))
        }
    }

    /// Iterates over all RX rings.
    public borrowing func forEachRxRing(_ body: (borrowing NetmapRing) throws -> Void) rethrows {
        for i in 0..<rxRingCount {
            try body(rxRing(i))
        }
    }

    /// Gets a host TX ring by index.
    ///
    /// Host TX rings contain packets being sent from applications
    /// to the network.
    ///
    /// - Parameter index: The ring index (0 to hostTxRingCount-1)
    /// - Returns: A borrowed reference to the host TX ring
    /// - Precondition: index < hostTxRingCount
    public borrowing func hostTxRing(_ index: UInt32) -> NetmapRing {
        precondition(index < hostTxRingCount, "Host TX ring index out of bounds")
        // Host rings follow NIC rings in the interface
        let ring = cnm_txring(nifpPtr, txRingCount + index)!
        return NetmapRing(ringPtr: ring, kind: .tx)
    }

    /// Gets a host RX ring by index.
    ///
    /// Host RX rings contain packets being delivered to applications.
    ///
    /// - Parameter index: The ring index (0 to hostRxRingCount-1)
    /// - Returns: A borrowed reference to the host RX ring
    /// - Precondition: index < hostRxRingCount
    public borrowing func hostRxRing(_ index: UInt32) -> NetmapRing {
        precondition(index < hostRxRingCount, "Host RX ring index out of bounds")
        // Host rings follow NIC rings in the interface
        let ring = cnm_rxring(nifpPtr, rxRingCount + index)!
        return NetmapRing(ringPtr: ring, kind: .rx)
    }

    /// Iterates over all host TX rings.
    public borrowing func forEachHostTxRing(_ body: (borrowing NetmapRing) throws -> Void) rethrows {
        for i in 0..<hostTxRingCount {
            try body(hostTxRing(i))
        }
    }

    /// Iterates over all host RX rings.
    public borrowing func forEachHostRxRing(_ body: (borrowing NetmapRing) throws -> Void) rethrows {
        for i in 0..<hostRxRingCount {
            try body(hostRxRing(i))
        }
    }

    /// Returns true if this port has host ring access.
    public var hasHostRings: Bool {
        return hostTxRingCount > 0 || hostRxRingCount > 0
    }

    // MARK: - Synchronization

    /// Synchronizes all TX rings with the hardware.
    ///
    /// Call this after filling TX slots to push packets to the NIC.
    public func txSync() throws {
        guard cnm_ioctl_txsync(fd) == 0 else {
            throw NetmapError.syncFailed(errno: errno)
        }
    }

    /// Synchronizes all RX rings with the hardware.
    ///
    /// Call this to fetch newly received packets from the NIC.
    public func rxSync() throws {
        guard cnm_ioctl_rxsync(fd) == 0 else {
            throw NetmapError.syncFailed(errno: errno)
        }
    }

    // MARK: - Polling

    /// Polls the port for events.
    ///
    /// - Parameters:
    ///   - events: Events to wait for
    ///   - timeout: Timeout in milliseconds (-1 for infinite)
    /// - Returns: Events that occurred
    /// - Throws: `NetmapError.pollFailed` on error
    public func poll(
        events: NetmapPollEvents,
        timeout: Int32 = -1
    ) throws -> NetmapPollEvents {
        let result = cnm_poll(fd, Int16(events.rawValue), timeout)
        if result < 0 {
            throw NetmapError.pollFailed(errno: errno)
        }
        // cnm_poll returns the actual revents (or 0 for timeout)
        return NetmapPollEvents(rawValue: Int16(result))
    }

    /// Waits for RX packets to arrive.
    ///
    /// - Parameter timeout: Timeout in milliseconds (-1 for infinite)
    /// - Returns: true if packets are available
    public func waitForRx(timeout: Int32 = -1) throws -> Bool {
        let events = try poll(events: .readable, timeout: timeout)
        return events.contains(.readable)
    }

    /// Waits for TX slots to become available.
    ///
    /// - Parameter timeout: Timeout in milliseconds (-1 for infinite)
    /// - Returns: true if slots are available
    public func waitForTx(timeout: Int32 = -1) throws -> Bool {
        let events = try poll(events: .writable, timeout: timeout)
        return events.contains(.writable)
    }

    // MARK: - Cleanup

    /// Closes the port and releases resources.
    ///
    /// After calling this method, the port is no longer usable.
    /// This is called automatically when the port goes out of scope.
    ///
    /// - Note: If the port was opened with external memory, the memory
    ///   is not unmapped (the caller retains ownership).
    public consuming func close() {
        if let mem = memBase, ownsMemory {
            _ = cnm_munmap(mem, memSize)
        }
        memBase = nil
        if fd >= 0 {
            Glibc.close(fd)
            fd = -1
        }
    }

    // MARK: - Port Information

    /// Gets information about a netmap port without registering.
    ///
    /// - Parameter interface: The interface name
    /// - Returns: Port information
    public static func getInfo(interface: String) throws -> NetmapPortInfo {
        guard interface.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(interface)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var info = nmreq_port_info_get()
        memset(&info, 0, MemoryLayout<nmreq_port_info_get>.size)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, interface, UInt16(CNM_REQ_PORT_INFO_GET), &info)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }

        return NetmapPortInfo(
            memorySize: info.nr_memsize,
            txSlots: info.nr_tx_slots,
            rxSlots: info.nr_rx_slots,
            txRings: info.nr_tx_rings,
            rxRings: info.nr_rx_rings,
            hostTxRings: info.nr_host_tx_rings,
            hostRxRings: info.nr_host_rx_rings,
            memoryId: info.nr_mem_id
        )
    }
}

/// Information about a netmap port.
public struct NetmapPortInfo: Sendable {
    /// Size of the shared memory region.
    public let memorySize: UInt64

    /// Number of slots per TX ring.
    public let txSlots: UInt32

    /// Number of slots per RX ring.
    public let rxSlots: UInt32

    /// Number of TX rings.
    public let txRings: UInt16

    /// Number of RX rings.
    public let rxRings: UInt16

    /// Number of host TX rings.
    public let hostTxRings: UInt16

    /// Number of host RX rings.
    public let hostRxRings: UInt16

    /// Memory allocator ID.
    public let memoryId: UInt16
}

// MARK: - Port Header Management

extension NetmapPort {
    /// Gets the current virtio-net header length for this port.
    ///
    /// Virtio-net headers are used for checksum and segmentation offload
    /// between VMs and the host.
    ///
    /// - Returns: The header length in bytes (0, 10, or 12 typically)
    /// - Throws: `NetmapError` if the operation fails
    public func getHeaderLength() throws -> UInt32 {
        var hdr = nmreq_port_hdr()
        cnm_init_port_hdr(&hdr, 0)

        var nmhdr = nmreq_header()
        cnm_init_header(&nmhdr, interfaceName, UInt16(CNM_REQ_PORT_HDR_GET), &hdr)

        guard cnm_ioctl_ctrl(fd, &nmhdr) == 0 else {
            throw NetmapError.syncFailed(errno: errno)
        }

        return cnm_port_hdr_len(&hdr)
    }

    /// Sets the virtio-net header length for this port.
    ///
    /// This is used when connecting netmap to VMs that expect virtio-net
    /// headers on packets. Valid values are typically 0, 10, or 12.
    ///
    /// - Parameter length: The header length in bytes
    /// - Throws: `NetmapError` if the operation fails
    public func setHeaderLength(_ length: UInt32) throws {
        var hdr = nmreq_port_hdr()
        cnm_init_port_hdr(&hdr, length)

        var nmhdr = nmreq_header()
        cnm_init_header(&nmhdr, interfaceName, UInt16(CNM_REQ_PORT_HDR_SET), &hdr)

        guard cnm_ioctl_ctrl(fd, &nmhdr) == 0 else {
            throw NetmapError.syncFailed(errno: errno)
        }
    }
}

// MARK: - Extra Buffers Management

extension NetmapPort {
    /// Head of the extra buffers list.
    ///
    /// Extra buffers are linked via the first uint32_t of each buffer.
    /// A value of 0 indicates the end of the list.
    public var extraBuffersHead: UInt32 {
        get {
            guard let nifp = nifpPtr else { return 0 }
            return cnm_if_bufs_head(nifp)
        }
        nonmutating set {
            guard let nifp = nifpPtr else { return }
            cnm_if_set_bufs_head(nifp, newValue)
        }
    }

    /// Iterates over all extra buffers.
    ///
    /// Extra buffers form a linked list where the first uint32_t of each
    /// buffer contains the index of the next buffer (0 = end of list).
    ///
    /// - Parameter body: Closure called with each buffer index
    /// - Note: Requires at least one ring to be available for offset calculations
    public borrowing func forEachExtraBuffer(_ body: (UInt32) throws -> Void) rethrows {
        guard txRingCount > 0 || rxRingCount > 0 else { return }

        let ring: NetmapRing
        if txRingCount > 0 {
            ring = txRing(0)
        } else {
            ring = rxRing(0)
        }

        var current = extraBuffersHead
        while current != 0 {
            try body(current)
            current = ring.getNextExtraBuffer(current)
        }
    }

    /// Pops a buffer from the extra buffers list.
    ///
    /// - Returns: The buffer index, or nil if the list is empty
    public func popExtraBuffer() -> UInt32? {
        guard txRingCount > 0 || rxRingCount > 0 else { return nil }

        let head = extraBuffersHead
        guard head != 0 else { return nil }

        let ring: NetmapRing
        if txRingCount > 0 {
            ring = txRing(0)
        } else {
            ring = rxRing(0)
        }

        // Update head to next buffer
        let next = ring.getNextExtraBuffer(head)
        extraBuffersHead = next

        return head
    }

    /// Pushes a buffer onto the extra buffers list.
    ///
    /// - Parameter bufferIndex: The buffer index to push
    public func pushExtraBuffer(_ bufferIndex: UInt32) {
        guard txRingCount > 0 || rxRingCount > 0 else { return }

        let ring: NetmapRing
        if txRingCount > 0 {
            ring = txRing(0)
        } else {
            ring = rxRing(0)
        }

        let oldHead = extraBuffersHead
        ring.setNextExtraBuffer(bufferIndex, next: oldHead)
        extraBuffersHead = bufferIndex
    }
}

// MARK: - Memory Pools Information

/// Information about netmap memory pools.
public struct NetmapPoolsInfo: Sendable {
    /// Total memory size.
    public let memorySize: UInt64

    /// Memory allocator ID.
    public let memoryId: UInt16

    /// Interface pool offset in memory.
    public let interfacePoolOffset: UInt64

    /// Total objects in interface pool.
    public let interfacePoolObjectCount: UInt32

    /// Size of each interface object.
    public let interfacePoolObjectSize: UInt32

    /// Ring pool offset in memory.
    public let ringPoolOffset: UInt64

    /// Total objects in ring pool.
    public let ringPoolObjectCount: UInt32

    /// Size of each ring object.
    public let ringPoolObjectSize: UInt32

    /// Buffer pool offset in memory.
    public let bufferPoolOffset: UInt64

    /// Total objects in buffer pool.
    public let bufferPoolObjectCount: UInt32

    /// Size of each buffer object.
    public let bufferPoolObjectSize: UInt32
}

extension NetmapPort {
    /// Gets detailed memory pool information for an interface.
    ///
    /// This provides low-level details about the netmap memory allocator,
    /// useful for advanced zero-copy operations and debugging.
    ///
    /// - Parameters:
    ///   - interface: Interface name to query (e.g., "vale0:test")
    ///   - memoryId: Memory allocator ID (0 for default)
    /// - Returns: Detailed pool information
    /// - Throws: `NetmapError` if the operation fails
    public static func getPoolsInfo(interface: String, memoryId: UInt16 = 0) throws -> NetmapPoolsInfo {
        guard interface.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(interface)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var info = nmreq_pools_info()
        cnm_init_pools_info(&info, memoryId)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, interface, UInt16(CNM_REQ_POOLS_INFO_GET), &info)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }

        return NetmapPoolsInfo(
            memorySize: info.nr_memsize,
            memoryId: info.nr_mem_id,
            interfacePoolOffset: info.nr_if_pool_offset,
            interfacePoolObjectCount: info.nr_if_pool_objtotal,
            interfacePoolObjectSize: info.nr_if_pool_objsize,
            ringPoolOffset: info.nr_ring_pool_offset,
            ringPoolObjectCount: info.nr_ring_pool_objtotal,
            ringPoolObjectSize: info.nr_ring_pool_objsize,
            bufferPoolOffset: info.nr_buf_pool_offset,
            bufferPoolObjectCount: info.nr_buf_pool_objtotal,
            bufferPoolObjectSize: info.nr_buf_pool_objsize
        )
    }

    /// Gets detailed memory pool information for this port.
    ///
    /// - Returns: Detailed pool information for this port's memory allocator
    /// - Throws: `NetmapError` if the operation fails
    public func getPoolsInfo() throws -> NetmapPoolsInfo {
        return try Self.getPoolsInfo(interface: interfaceName)
    }
}
