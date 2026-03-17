/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Foundation
import Glibc

// MARK: - MessageCredentials

/// Credentials delivered with each message via `LOCAL_CREDS_PERSISTENT`.
///
/// Unlike ``PeerCredentials`` (from `LOCAL_PEERCRED`), this provides:
/// - **Real** user/group IDs (not just effective)
/// - Per-message credentials (not just at connection time)
/// - Both real and effective credentials for comparison
///
/// ## Credential Comparison
///
/// | Aspect | `PeerCredentials` | `MessageCredentials` |
/// |--------|-------------------|----------------------|
/// | Source | `LOCAL_PEERCRED` via `getsockopt()` | `LOCAL_CREDS_PERSISTENT` via `recvmsg()` |
/// | Credential Type | Effective only (euid/egid) | Real and effective |
/// | Delivery | On-demand query | Every message automatically |
/// | Structure | `xucred` | `sockcred2` |
///
/// ## Setuid Detection
///
/// One key advantage of `MessageCredentials` is the ability to detect setuid/setgid
/// processes by comparing real and effective credentials:
///
/// ```swift
/// if let creds = message.senderCredentials {
///     if creds.isSetuid {
///         print("Warning: Message from setuid process")
///         print("Real UID: \(creds.realUID), Effective UID: \(creds.effectiveUID)")
///     }
/// }
/// ```
///
/// ## Usage
///
/// ```swift
/// for await message in endpoint.incoming() {
///     if let creds = message.senderCredentials {
///         print("From PID \(creds.pid), real UID \(creds.realUID)")
///
///         // Check for privilege escalation
///         if creds.isSetuid || creds.isSetgid {
///             print("Process running with elevated privileges")
///         }
///     }
/// }
/// ```
public struct MessageCredentials: Sendable, Equatable, Hashable {
    /// Real user ID of the sending process.
    ///
    /// This is the actual user who started the process, not the effective UID
    /// which may differ for setuid binaries.
    public let realUID: uid_t

    /// Effective user ID of the sending process.
    ///
    /// For setuid binaries, this differs from `realUID` and represents
    /// the elevated privileges the process is running with.
    public let effectiveUID: uid_t

    /// Real group ID of the sending process.
    ///
    /// This is the actual group of the user who started the process.
    public let realGID: gid_t

    /// Effective group ID of the sending process.
    ///
    /// For setgid binaries, this differs from `realGID`.
    public let effectiveGID: gid_t

    /// Process ID of the sending process.
    public let pid: pid_t

    /// Supplementary groups of the sending process.
    ///
    /// This includes all groups the process is a member of.
    public let groups: [gid_t]

    /// True if the process is running with elevated user privileges (euid != ruid).
    ///
    /// This indicates a setuid binary where the effective UID differs from the
    /// real UID of the user who executed it.
    public var isSetuid: Bool { effectiveUID != realUID }

    /// True if the process is running with elevated group privileges (egid != rgid).
    ///
    /// This indicates a setgid binary where the effective GID differs from the
    /// real GID of the user who executed it.
    public var isSetgid: Bool { effectiveGID != realGID }

    /// True if the process is running as effective root (euid == 0).
    public var isEffectiveRoot: Bool { effectiveUID == 0 }

    /// True if the process was started by real root (ruid == 0).
    public var isRealRoot: Bool { realUID == 0 }

    /// Checks if the process is a member of the specified group.
    ///
    /// This checks the effective GID and all supplementary groups.
    ///
    /// - Parameter group: The group ID to check membership for.
    /// - Returns: `true` if the process is a member of the group.
    public func isMemberOf(group: gid_t) -> Bool {
        effectiveGID == group || groups.contains(group)
    }

    public init(
        realUID: uid_t,
        effectiveUID: uid_t,
        realGID: gid_t,
        effectiveGID: gid_t,
        pid: pid_t,
        groups: [gid_t] = []
    ) {
        self.realUID = realUID
        self.effectiveUID = effectiveUID
        self.realGID = realGID
        self.effectiveGID = effectiveGID
        self.pid = pid
        self.groups = groups
    }
}

// MARK: - CustomStringConvertible

extension MessageCredentials: CustomStringConvertible {
    public var description: String {
        var desc = "MessageCredentials(pid: \(pid), ruid: \(realUID), euid: \(effectiveUID), rgid: \(realGID), egid: \(effectiveGID)"
        if isSetuid {
            desc += ", setuid"
        }
        if isSetgid {
            desc += ", setgid"
        }
        desc += ")"
        return desc
    }
}
