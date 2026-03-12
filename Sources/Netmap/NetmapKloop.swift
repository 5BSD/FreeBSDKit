/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CNetmap
import Foundation
import Glibc

/// Kernel sync loop (kloop) for ultra-low latency packet processing.
///
/// The sync kloop runs a busy-poll loop inside the kernel, synchronizing
/// rings without requiring userspace intervention. This provides the
/// lowest possible latency at the cost of dedicating CPU cores to polling.
///
/// ## How It Works
///
/// When you start a kloop, the ioctl blocks and the kernel continuously
/// syncs the rings. The application can:
/// - Process packets in shared memory while the kernel syncs
/// - Use the `sleep_us` parameter to control polling frequency
/// - Stop the loop from another thread using `stopKloop()`
///
/// ## Example Usage
///
/// ```swift
/// // Start kloop in a background thread
/// let port = try NetmapPort.open(interface: "vale0:kloop")
///
/// Task {
///     do {
///         // This blocks until stopped
///         try NetmapKloop.startKloop(port: port, sleepMicroseconds: 0)
///     } catch {
///         print("Kloop stopped: \(error)")
///     }
/// }
///
/// // Process packets in main thread
/// while running {
///     let ring = port.rxRing(0)
///     while !ring.isEmpty {
///         // Process packet...
///         ring.advance()
///     }
/// }
///
/// // Stop the kloop
/// try NetmapKloop.stopKloop(port: port)
/// ```
///
/// ## Performance Considerations
///
/// - `sleepMicroseconds = 0`: Maximum performance, 100% CPU usage
/// - `sleepMicroseconds > 0`: Reduced CPU usage but higher latency
/// - Typical values: 0-100 microseconds depending on latency requirements
///
/// - Note: Kloop requires the port to remain open while the loop runs.
///   Closing the port will terminate the kloop.
public enum NetmapKloop {

    /// Starts a kernel sync loop on the specified port.
    ///
    /// This call blocks until the kloop is stopped by calling `stopKloop()`
    /// from another thread, or until an error occurs.
    ///
    /// - Parameters:
    ///   - port: The netmap port to run the kloop on
    ///   - sleepMicroseconds: Microseconds to sleep between sync iterations
    ///     (0 for busy-poll, higher values reduce CPU usage)
    /// - Throws: `NetmapError` if the kloop fails to start or encounters an error
    ///
    /// - Important: This method blocks. Call it from a background thread.
    public static func startKloop(
        port: borrowing NetmapPort,
        sleepMicroseconds: UInt32 = 0
    ) throws {
        var kloop = nmreq_sync_kloop_start()
        cnm_init_sync_kloop_start(&kloop, sleepMicroseconds)

        var hdr = nmreq_header()
        cnm_init_header(&hdr, port.interfaceName, UInt16(CNM_REQ_SYNC_KLOOP_START), &kloop)

        // This ioctl blocks until the kloop is stopped
        guard cnm_ioctl_ctrl(port.fileDescriptor, &hdr) == 0 else {
            let err = errno
            // EINTR means we were interrupted (normal stop)
            if err == EINTR {
                return
            }
            throw NetmapError.syncFailed(errno: err)
        }
    }

    /// Stops a running kernel sync loop.
    ///
    /// This sends a stop request to the kernel, causing the blocking
    /// `startKloop()` call to return.
    ///
    /// - Parameter port: The netmap port running the kloop
    /// - Throws: `NetmapError` if the stop request fails
    public static func stopKloop(port: borrowing NetmapPort) throws {
        var hdr = nmreq_header()
        cnm_init_header(&hdr, port.interfaceName, UInt16(CNM_REQ_SYNC_KLOOP_STOP), nil)

        guard cnm_ioctl_ctrl(port.fileDescriptor, &hdr) == 0 else {
            throw NetmapError.syncFailed(errno: errno)
        }
    }

    /// Configuration for running a kloop with automatic management.
    public struct Config: Sendable {
        /// Microseconds to sleep between sync iterations.
        public var sleepMicroseconds: UInt32

        /// Creates a kloop configuration.
        ///
        /// - Parameter sleepMicroseconds: Sleep time between iterations (0 for busy-poll)
        public init(sleepMicroseconds: UInt32 = 0) {
            self.sleepMicroseconds = sleepMicroseconds
        }

        /// Busy-poll configuration (maximum performance, 100% CPU).
        public static let busyPoll = Config(sleepMicroseconds: 0)

        /// Low-latency configuration (good balance).
        public static let lowLatency = Config(sleepMicroseconds: 10)

        /// Power-saving configuration (reduced CPU usage).
        public static let powerSaving = Config(sleepMicroseconds: 100)
    }
}

// MARK: - NetmapPort Kloop Extension

extension NetmapPort {

    /// Starts a kernel sync loop on this port.
    ///
    /// This call blocks until the kloop is stopped. See `NetmapKloop` for details.
    ///
    /// - Parameter sleepMicroseconds: Microseconds to sleep between iterations
    /// - Throws: `NetmapError` if the kloop fails
    public func startKloop(sleepMicroseconds: UInt32 = 0) throws {
        try NetmapKloop.startKloop(port: self, sleepMicroseconds: sleepMicroseconds)
    }

    /// Stops the kernel sync loop on this port.
    ///
    /// - Throws: `NetmapError` if the stop request fails
    public func stopKloop() throws {
        try NetmapKloop.stopKloop(port: self)
    }
}
