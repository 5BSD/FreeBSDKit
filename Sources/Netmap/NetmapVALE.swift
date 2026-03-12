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

/// VALE switch management operations.
///
/// VALE is a software Ethernet switch built into netmap that provides
/// high-performance L2 switching between netmap ports. VALE switches
/// support:
///
/// - Zero-copy packet forwarding between ports
/// - Learning bridge with MAC address table
/// - Broadcast/multicast handling
/// - Virtual interfaces for host stack connectivity
///
/// ## Creating a VALE Switch
///
/// VALE switches are created implicitly when you attach the first port:
///
/// ```swift
/// // Attaching a port creates the switch if it doesn't exist
/// let portIndex = try NetmapVALE.attach(
///     switch: "vale0",
///     port: "myport"
/// )
/// ```
///
/// ## Listing Ports
///
/// ```swift
/// let ports = try NetmapVALE.listPorts(switch: "vale0")
/// for port in ports {
///     print("Port \(port.index): \(port.name)")
/// }
/// ```
///
/// ## Virtual Interfaces
///
/// Create persistent virtual interfaces on a VALE switch:
///
/// ```swift
/// // Create a virtual interface
/// try NetmapVALE.createInterface(
///     name: "vale0:vif0",
///     txRings: 2,
///     rxRings: 2
/// )
///
/// // Delete when done
/// try NetmapVALE.deleteInterface(name: "vale0:vif0")
/// ```
public enum NetmapVALE {

    // MARK: - Port Attachment

    /// Attaches a netmap port to a VALE switch.
    ///
    /// The port is identified by its netmap name (e.g., "em0" for a NIC,
    /// "vale1:port" for another VALE port). The switch is created
    /// automatically if it doesn't exist.
    ///
    /// - Parameters:
    ///   - switchName: The VALE switch name (e.g., "vale0")
    ///   - portName: The port name to attach (e.g., "myport")
    ///   - mode: Registration mode (default: all NIC rings)
    ///   - flags: Registration flags
    /// - Returns: The port index assigned by the switch
    /// - Throws: `NetmapError` if attachment fails
    public static func attach(
        switch switchName: String,
        port portName: String,
        mode: NetmapRegistrationMode = .allNIC,
        flags: NetmapRegistrationFlags = []
    ) throws -> UInt32 {
        let fullName = "\(switchName):\(portName)"
        guard fullName.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(fullName)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var attach = nmreq_vale_attach()
        cnm_init_vale_attach(&attach, mode.rawValue, flags.rawValue)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, fullName, UInt16(CNM_REQ_VALE_ATTACH), &attach)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }

        return cnm_vale_attach_port_index(&attach)
    }

    /// Detaches a port from a VALE switch.
    ///
    /// - Parameters:
    ///   - switchName: The VALE switch name
    ///   - portName: The port name to detach
    /// - Returns: The port index that was detached
    /// - Throws: `NetmapError` if detachment fails
    @discardableResult
    public static func detach(
        switch switchName: String,
        port portName: String
    ) throws -> UInt32 {
        let fullName = "\(switchName):\(portName)"
        guard fullName.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(fullName)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var detach = nmreq_vale_detach()
        cnm_init_vale_detach(&detach)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, fullName, UInt16(CNM_REQ_VALE_DETACH), &detach)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }

        return cnm_vale_detach_port_index(&detach)
    }

    // MARK: - Port Listing

    /// Information about a port on a VALE switch.
    public struct PortInfo: Sendable {
        /// The port index on the switch.
        public let index: UInt32

        /// The port name.
        public let name: String

        /// The bridge index (for multi-bridge configurations).
        public let bridgeIndex: UInt16
    }

    /// Lists all ports attached to a VALE switch.
    ///
    /// - Parameter switchName: The VALE switch name (e.g., "vale0")
    /// - Returns: Array of port information
    /// - Throws: `NetmapError` if listing fails
    ///
    /// - Note: This requires at least one port to be currently attached
    ///   to the switch. If no ports are attached, an empty array is returned.
    public static func listPorts(switch switchName: String) throws -> [PortInfo] {
        // VALE_LIST requires the switch name with a trailing colon
        let queryName = switchName.hasSuffix(":") ? switchName : switchName + ":"

        guard queryName.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(switchName)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var ports: [PortInfo] = []
        var portIdx: UInt32 = 0
        let maxPorts: UInt32 = 256  // Safety limit

        while portIdx < maxPorts {
            var list = nmreq_vale_list()
            cnm_init_vale_list(&list)
            cnm_vale_list_set_port_idx(&list, portIdx)

            var hdr = nmreq_header()
            cnm_init_header(&hdr, queryName, UInt16(CNM_REQ_VALE_LIST), &list)

            let result = cnm_ioctl_ctrl(fd, &hdr)
            if result != 0 {
                let err = errno
                // EINVAL means no more ports, ENOENT means switch doesn't exist/empty
                // ENODEV (19) also indicates end of list
                if err == EINVAL || err == ENOENT || err == ENODEV || err == 19 {
                    break
                }
                // EOPNOTSUPP means VALE_LIST isn't supported
                if err == EOPNOTSUPP || err == 45 {
                    break
                }
                throw NetmapError.registerFailed(errno: err)
            }

            // Extract port name from header
            let name = withUnsafePointer(to: hdr.nr_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(CNM_REQ_IFNAMSIZ)) {
                    String(cString: $0)
                }
            }

            // Empty name means no more ports
            if name.isEmpty || name == queryName {
                break
            }

            let returnedIdx = cnm_vale_list_port_idx(&list)

            let info = PortInfo(
                index: returnedIdx,
                name: name,
                bridgeIndex: cnm_vale_list_bridge_idx(&list)
            )
            ports.append(info)

            // Move to next port
            portIdx = returnedIdx + 1
        }

        return ports
    }

    // MARK: - Virtual Interface Management

    /// Configuration for a new VALE virtual interface.
    public struct InterfaceConfig: Sendable {
        /// Number of TX slots per ring (0 for default).
        public var txSlots: UInt32

        /// Number of RX slots per ring (0 for default).
        public var rxSlots: UInt32

        /// Number of TX rings (0 for default).
        public var txRings: UInt16

        /// Number of RX rings (0 for default).
        public var rxRings: UInt16

        /// Memory allocator ID (0 for default).
        public var memoryId: UInt16

        /// Creates a configuration with default values.
        public init(
            txSlots: UInt32 = 0,
            rxSlots: UInt32 = 0,
            txRings: UInt16 = 0,
            rxRings: UInt16 = 0,
            memoryId: UInt16 = 0
        ) {
            self.txSlots = txSlots
            self.rxSlots = rxSlots
            self.txRings = txRings
            self.rxRings = rxRings
            self.memoryId = memoryId
        }
    }

    /// Creates a persistent virtual interface on a VALE switch.
    ///
    /// Virtual interfaces (vifs) are persistent netmap ports that exist
    /// independently of any process. They're useful for:
    /// - Connecting VMs or containers to a VALE switch
    /// - Creating tap-like interfaces for the host stack
    /// - Building complex virtual network topologies
    ///
    /// - Parameters:
    ///   - name: The interface name (e.g., "vale0:vif0")
    ///   - config: Interface configuration (optional)
    /// - Returns: The memory ID assigned to the interface
    /// - Throws: `NetmapError` if creation fails
    @discardableResult
    public static func createInterface(
        name: String,
        config: InterfaceConfig = InterfaceConfig()
    ) throws -> UInt16 {
        guard name.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(name)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var newif = nmreq_vale_newif()
        cnm_init_vale_newif(
            &newif,
            config.txSlots,
            config.rxSlots,
            config.txRings,
            config.rxRings,
            config.memoryId
        )

        var hdr = nmreq_header()
        cnm_init_header(&hdr, name, UInt16(CNM_REQ_VALE_NEWIF), &newif)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }

        return cnm_vale_newif_mem_id(&newif)
    }

    /// Deletes a persistent virtual interface from a VALE switch.
    ///
    /// - Parameter name: The interface name to delete
    /// - Throws: `NetmapError` if deletion fails
    public static func deleteInterface(name: String) throws {
        guard name.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(name)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        // VALE_DELIF doesn't need a body structure
        var hdr = nmreq_header()
        cnm_init_header(&hdr, name, UInt16(CNM_REQ_VALE_DELIF), nil)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }
    }

    // MARK: - Utility Methods

    /// Checks if a name refers to a VALE switch.
    ///
    /// VALE switch names start with "vale" (e.g., "vale0", "vale1:port").
    ///
    /// - Parameter name: The name to check
    /// - Returns: true if the name is a VALE switch name
    public static func isVALEName(_ name: String) -> Bool {
        return name.hasPrefix("vale")
    }

    /// Parses a VALE port name into switch and port components.
    ///
    /// - Parameter fullName: The full port name (e.g., "vale0:myport")
    /// - Returns: Tuple of (switchName, portName), or nil if not a valid VALE name
    public static func parseVALEName(_ fullName: String) -> (switchName: String, portName: String)? {
        guard isVALEName(fullName) else { return nil }

        if let colonIndex = fullName.firstIndex(of: ":") {
            let switchName = String(fullName[..<colonIndex])
            let portName = String(fullName[fullName.index(after: colonIndex)...])
            return (switchName, portName)
        }

        // Just the switch name, no port
        return (fullName, "")
    }

    // MARK: - Polling Control

    /// Polling mode for VALE switch.
    public enum PollingMode: UInt32, Sendable {
        /// Single CPU polling mode.
        case singleCPU = 1

        /// Multi-CPU polling mode.
        case multiCPU = 2
    }

    /// Configuration for VALE polling.
    public struct PollingConfig: Sendable {
        /// Polling mode.
        public var mode: PollingMode

        /// First CPU ID to use for polling.
        public var firstCPU: UInt32

        /// Number of CPUs to use for polling.
        public var cpuCount: UInt32

        /// Creates a polling configuration.
        ///
        /// - Parameters:
        ///   - mode: Polling mode
        ///   - firstCPU: First CPU ID
        ///   - cpuCount: Number of CPUs
        public init(mode: PollingMode = .singleCPU, firstCPU: UInt32 = 0, cpuCount: UInt32 = 1) {
            self.mode = mode
            self.firstCPU = firstCPU
            self.cpuCount = cpuCount
        }
    }

    /// Enables polling mode on a VALE switch port.
    ///
    /// Polling mode uses busy-polling instead of interrupts, which can
    /// significantly reduce latency at the cost of CPU usage.
    ///
    /// - Parameters:
    ///   - name: The VALE port name (e.g., "vale0:myport")
    ///   - config: Polling configuration
    /// - Throws: `NetmapError` if enabling fails
    ///
    /// - Note: Polling mode requires appropriate CPU affinity setup and
    ///   is typically used in high-performance networking scenarios.
    public static func enablePolling(name: String, config: PollingConfig = PollingConfig()) throws {
        guard name.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(name)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var poll = nmreq_vale_polling()
        cnm_init_vale_polling(&poll, config.mode.rawValue, config.firstCPU, config.cpuCount)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, name, UInt16(CNM_REQ_VALE_POLLING_ENABLE), &poll)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }
    }

    /// Disables polling mode on a VALE switch port.
    ///
    /// - Parameter name: The VALE port name
    /// - Throws: `NetmapError` if disabling fails
    public static func disablePolling(name: String) throws {
        guard name.utf8.count < Int(CNM_REQ_IFNAMSIZ) else {
            throw NetmapError.invalidInterfaceName(name)
        }

        let fd = Glibc.open(netmapDevicePath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw NetmapError.openFailed(errno: errno)
        }
        defer { Glibc.close(fd) }

        var poll = nmreq_vale_polling()
        cnm_init_vale_polling(&poll, 0, 0, 0)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, name, UInt16(CNM_REQ_VALE_POLLING_DISABLE), &poll)

        guard cnm_ioctl_ctrl(fd, &hdr) == 0 else {
            throw NetmapError.registerFailed(errno: errno)
        }
    }
}
