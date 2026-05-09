# Getting Started with FreeBSDKit

Learn how to add FreeBSDKit to your Swift project and start using FreeBSD system features.

## Overview

FreeBSDKit is a Swift framework that provides idiomatic APIs for FreeBSD-specific system features. It wraps low-level system calls in safe, type-aware Swift interfaces.

## Requirements

- FreeBSD 13.0 or later
- Swift 6.3 development snapshot or later
- Root privileges for most operations

## Adding FreeBSDKit to Your Project

Add FreeBSDKit as a dependency in your `Package.swift`:

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(url: "https://github.com/SwiftBSD/FreeBSDKit", from: "0.2.6")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "FreeBSDKit", package: "FreeBSDKit"),
                .product(name: "Capsicum", package: "FreeBSDKit"),
                .product(name: "Capabilities", package: "FreeBSDKit"),
                .product(name: "Descriptors", package: "FreeBSDKit"),
                .product(name: "Jails", package: "FreeBSDKit"),
            ]
        )
    ]
)
```

## Available Modules

FreeBSDKit is organized into several modules:

| Module | Description |
|--------|-------------|
| **FreeBSDKit** | Core types and utilities |
| **Capsicum** | Capability-based sandboxing |
| **Capabilities** | Type-safe file descriptor wrappers |
| **Descriptors** | Low-level descriptor protocols |
| **Jails** | Jail creation and management |
| **FPC** | FreeBSD Privilege-separated Communication |
| **Casper** | Casper helper services |
| **MacLabel** | Mandatory Access Control labels |
| **Audit** | BSM audit event monitoring |
| **Rctl** | Resource limits |
| **Cpuset** | CPU affinity |
| **Procctl** | Process control |
| **ACL** | Access Control Lists |

## Your First Program

Here's a simple program that uses FreeBSDKit to read extended attributes:

```swift
import FreeBSDKit
import Foundation

// Read an extended attribute from a file
let path = "/tmp/testfile"

// Create a test file
FileManager.default.createFile(atPath: path, contents: nil)

// Set an extended attribute
try ExtendedAttribute.set(
    name: "user.example",
    value: Data("Hello, FreeBSD!".utf8),
    path: path
)

// Read it back
if let data = try ExtendedAttribute.get(name: "user.example", path: path) {
    print(String(data: data, encoding: .utf8)!)
}
```

## Next Steps

- Follow the <doc:Tutorials/FreeBSDKitByExample> tutorial series
- Read about <doc:CapsicumOverview> for sandboxing
- Learn about <doc:JailsOverview> for containerization
