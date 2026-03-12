/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Foundation

/// Errors that can occur during netmap operations.
public enum NetmapError: Error, CustomStringConvertible {
    /// Failed to open the netmap device.
    case openFailed(errno: Int32)

    /// Failed to register the interface.
    case registerFailed(errno: Int32)

    /// Failed to memory map the netmap region.
    case mmapFailed(errno: Int32)

    /// Invalid interface name.
    case invalidInterfaceName(String)

    /// Ring index out of bounds.
    case ringIndexOutOfBounds(index: UInt32, max: UInt32)

    /// Slot index out of bounds.
    case slotIndexOutOfBounds(index: UInt32, max: UInt32)

    /// No slots available in ring.
    case noSlotsAvailable

    /// Sync operation failed.
    case syncFailed(errno: Int32)

    /// Poll operation failed.
    case pollFailed(errno: Int32)

    /// Port is not registered.
    case notRegistered

    /// Buffer too large for slot.
    case bufferTooLarge(size: Int, maxSize: Int)

    /// Invalid operation for ring type.
    case invalidRingType(expected: String, got: String)

    /// Invalid configuration.
    case invalidConfiguration(String)

    /// Memory allocation failed.
    case allocationFailed

    /// Option was rejected by kernel.
    case optionRejected(option: String, errno: Int32)

    public var description: String {
        switch self {
        case .openFailed(let errno):
            return "Failed to open /dev/netmap: \(String(cString: strerror(errno)))"
        case .registerFailed(let errno):
            return "Failed to register interface: \(String(cString: strerror(errno)))"
        case .mmapFailed(let errno):
            return "Failed to mmap netmap region: \(String(cString: strerror(errno)))"
        case .invalidInterfaceName(let name):
            return "Invalid interface name: \(name)"
        case .ringIndexOutOfBounds(let index, let max):
            return "Ring index \(index) out of bounds (max \(max))"
        case .slotIndexOutOfBounds(let index, let max):
            return "Slot index \(index) out of bounds (max \(max))"
        case .noSlotsAvailable:
            return "No slots available in ring"
        case .syncFailed(let errno):
            return "Sync failed: \(String(cString: strerror(errno)))"
        case .pollFailed(let errno):
            return "Poll failed: \(String(cString: strerror(errno)))"
        case .notRegistered:
            return "Port is not registered"
        case .bufferTooLarge(let size, let maxSize):
            return "Buffer size \(size) exceeds maximum \(maxSize)"
        case .invalidRingType(let expected, let got):
            return "Invalid ring type: expected \(expected), got \(got)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .allocationFailed:
            return "Memory allocation failed"
        case .optionRejected(let option, let errno):
            return "Option \(option) rejected: \(String(cString: strerror(errno)))"
        }
    }
}
