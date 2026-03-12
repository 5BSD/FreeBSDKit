/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap

/// Registration mode for netmap ports.
///
/// Determines which rings are bound when registering a netmap port.
public enum NetmapRegistrationMode: UInt32, Sendable {
    /// Backward compatibility, should not be used.
    case `default` = 0

    /// All NIC rings (no host rings).
    case allNIC = 1

    /// Only host stack rings (software rings).
    case hostOnly = 2

    /// All NIC rings plus host stack rings.
    case nicAndHost = 3

    /// A single NIC ring pair (specified by ringid).
    case oneNIC = 4

    /// Master side of a netmap pipe.
    case pipeMaster = 5

    /// Slave side of a netmap pipe.
    case pipeSlave = 6

    /// Null port (for testing).
    case null = 7

    /// A single host ring pair.
    case oneHost = 8

    /// Create from raw value, defaulting to allNIC.
    public init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .default
        case 1: self = .allNIC
        case 2: self = .hostOnly
        case 3: self = .nicAndHost
        case 4: self = .oneNIC
        case 5: self = .pipeMaster
        case 6: self = .pipeSlave
        case 7: self = .null
        case 8: self = .oneHost
        default: self = .allNIC
        }
    }
}

/// Flags for netmap port registration.
public struct NetmapRegistrationFlags: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// Monitor TX ring (copy mode).
    public static let monitorTX = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_MONITOR_TX))

    /// Monitor RX ring (copy mode).
    public static let monitorRX = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_MONITOR_RX))

    /// Zero-copy monitor mode.
    public static let zeroCopyMonitor = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_ZCOPY_MON))

    /// Exclusive access to selected rings.
    public static let exclusive = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_EXCLUSIVE))

    /// Bind only RX rings.
    public static let rxRingsOnly = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_RX_RINGS_ONLY))

    /// Bind only TX rings.
    public static let txRingsOnly = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_TX_RINGS_ONLY))

    /// Accept virtio-net header.
    public static let acceptVnetHeader = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_ACCEPT_VNET_HDR))

    /// Release RX packets on poll even without POLLIN.
    public static let doRXPoll = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_DO_RX_POLL))

    /// Don't push TX packets on poll without POLLOUT.
    public static let noTXPoll = NetmapRegistrationFlags(rawValue: UInt64(CNM_NR_NO_TX_POLL))
}

/// Flags for netmap slots.
public struct NetmapSlotFlags: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// Buffer index changed (must set when changing buf_idx).
    public static let bufferChanged = NetmapSlotFlags(rawValue: UInt16(CNM_NS_BUF_CHANGED))

    /// Request notification when slot is transmitted.
    public static let report = NetmapSlotFlags(rawValue: UInt16(CNM_NS_REPORT))

    /// Forward packet to peer ring (host/NIC).
    public static let forward = NetmapSlotFlags(rawValue: UInt16(CNM_NS_FORWARD))

    /// Don't learn source port on VALE switch.
    public static let noLearn = NetmapSlotFlags(rawValue: UInt16(CNM_NS_NO_LEARN))

    /// Data is in userspace buffer (ptr field).
    public static let indirect = NetmapSlotFlags(rawValue: UInt16(CNM_NS_INDIRECT))

    /// More fragments follow.
    public static let moreFragments = NetmapSlotFlags(rawValue: UInt16(CNM_NS_MOREFRAG))

    /// Packet from TX monitor.
    public static let txMonitor = NetmapSlotFlags(rawValue: UInt16(CNM_NS_TXMON))
}

/// Flags for netmap rings.
public struct NetmapRingFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Set timestamp on sync operations.
    public static let timestamp = NetmapRingFlags(rawValue: CNM_NR_TIMESTAMP)

    /// Enable NS_FORWARD for ring.
    public static let forward = NetmapRingFlags(rawValue: CNM_NR_FORWARD)
}

/// Events for polling netmap file descriptors.
public struct NetmapPollEvents: OptionSet, Sendable {
    public let rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    /// Ready to receive (RX ring has packets).
    public static let readable = NetmapPollEvents(rawValue: Int16(CNM_POLLIN))

    /// Ready to transmit (TX ring has slots).
    public static let writable = NetmapPollEvents(rawValue: Int16(CNM_POLLOUT))

    /// Error condition.
    public static let error = NetmapPollEvents(rawValue: Int16(CNM_POLLERR))

    /// Both readable and writable.
    public static let readWrite: NetmapPollEvents = [.readable, .writable]
}
