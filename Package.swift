// swift-tools-version: 6.3
//
// This package requires Swift 6.3 (development snapshot) which is not yet available
// in FreeBSD ports. You must install Swift from the CI nightly builds:
// https://download.swift.org/tmp-ci-nightly/development/freebsd-14_ci_latest.tar.gz
//
// The ports version of Swift (currently 5.10) does not support the language features
// used by this package (e.g., ~Copyable).

import PackageDescription



let package = Package(
    name: "FreeBSDKit",
    products: [
        .library(
            name: "FreeBSDKit",
            targets: ["FreeBSDKit"]
        ),
        .library(
            name: "Capsicum",
            targets: ["Capsicum"]
        ),
        .library(
            name: "Capabilites",
            targets: ["Capsicum"]
        ),
        .library(
            name: "Descriptors",
            targets: ["Descriptors"]
        ),
        .library(
            name: "SignalDispatchers",
            targets: ["SignalDispatchers"]
        ),
        .library(
            name: "FPC",
            targets: ["FPC"]
        ),
        .library(
            name: "MacLabel",
            targets: ["MacLabel"]
        ),
        .library(
            name: "CMacLabelParser",
            targets: ["CMacLabelParser"]
        ),
        .library(
            name: "Casper",
            targets: ["Casper"]
        ),
        .library(
            name: "Procctl",
            targets: ["Procctl"]
        ),
        .library(
            name: "ACL",
            targets: ["ACL"]
        ),
        .library(
            name: "Rctl",
            targets: ["Rctl"]
        ),
        .library(
            name: "Cpuset",
            targets: ["Cpuset"]
        ),
        .library(
            name: "Audit",
            targets: ["Audit"]
        ),
        .library(
            name: "DTraceCore",
            targets: ["DTraceCore"]
        ),
        .library(
            name: "DBlocks",
            targets: ["DBlocks"]
        ),
        .library(
            name: "AgeSignal",
            targets: ["AgeSignal"]
        ),
        .library(
            name: "Netmap",
            targets: ["Netmap"]
        ),
        .executable(
            name: "maclabel",
            targets: ["maclabel"]
        ),
        .executable(
            name: "acl-demo",
            targets: ["acl-demo"]
        ),
        .executable(
            name: "fpc-demo",
            targets: ["fpc-demo"]
        ),
        .executable(
            name: "dprobes",
            targets: ["dprobes-cli"]
        ),
        .executable(
            name: "aged",
            targets: ["aged"]
        ),
        .executable(
            name: "agectl",
            targets: ["agectl"]
        ),
        .executable(
            name: "jails-demo",
            targets: ["jails-demo"]
        ),
        .executable(
            name: "kqueue-demo",
            targets: ["kqueue-demo"]
        ),
        .executable(
            name: "netmap-demo",
            targets: ["netmap-demo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "FreeBSDKit",
            dependencies: ["CExtendedAttributes"]
        ),
        .target(
            name: "CCapsicum",
            path: "Sources/CCapsicum"
        ),
        .target(
            name: "CExtendedAttributes",
            path: "Sources/CExtendedAttributes"
        ),
        .target(
            name: "Capsicum",
            dependencies: ["CCapsicum", "FreeBSDKit"]
        ),
        .target(
            name: "CProcessDescriptor",
            path: "Sources/CProcessDescriptor"
        ),
        .target(
            name: "CJails",
            path: "Sources/CJails"
        ),
        .target(
            name: "Jails",
            dependencies: ["CJails", "FreeBSDKit"],
            path: "Sources/Jails",
            linkerSettings: [
                .linkedLibrary("jail")
            ]
        ),
        .target(
            name: "CEventDescriptor",
            path: "Sources/CEventDescriptor"
        ),
        .target(
            name: "CINotify",
            path: "Sources/CINotify"
        ),
        .target(
            name: "CSignal",
            path: "Sources/CSignal"
        ),
        .target(
            name: "CDeviceIoctl",
            path: "Sources/CDeviceIoctl"
        ),
        .target(
            name: "CNetmap",
            path: "Sources/CNetmap"
        ),
        .target(
            name: "CCasper",
            path: "Sources/CCasper",
            linkerSettings: [
                .linkedLibrary("casper"),
                .linkedLibrary("cap_dns"),
                .linkedLibrary("cap_sysctl"),
                .linkedLibrary("cap_pwd"),
                .linkedLibrary("cap_grp"),
                .linkedLibrary("cap_syslog"),
                .linkedLibrary("cap_fileargs"),
                .linkedLibrary("cap_net"),
                .linkedLibrary("cap_netdb")
            ]
        ),
        .target(
            name: "Casper",
            dependencies: ["CCasper", "FreeBSDKit"]
        ),
        .target(
            name: "CProcctl",
            path: "Sources/CProcctl"
        ),
        .target(
            name: "Procctl",
            dependencies: ["CProcctl", "FreeBSDKit"]
        ),
        .target(
            name: "CACL",
            path: "Sources/CACL"
        ),
        .target(
            name: "ACL",
            dependencies: ["CACL", "Descriptors"]
        ),
        .target(
            name: "CRctl",
            path: "Sources/CRctl"
        ),
        .target(
            name: "Rctl",
            dependencies: ["CRctl", "Descriptors"]
        ),
        .target(
            name: "CCpuset",
            path: "Sources/CCpuset"
        ),
        .target(
            name: "Cpuset",
            dependencies: ["CCpuset", "Descriptors"]
        ),
        .target(
            name: "CAudit",
            path: "Sources/CAudit",
            linkerSettings: [
                .linkedLibrary("bsm")
            ]
        ),
        .target(
            name: "Audit",
            dependencies: ["CAudit", "Descriptors"],
            linkerSettings: [
                .linkedLibrary("bsm")
            ]
        ),
        .target(
            name: "Descriptors",
            dependencies: [
                "Capsicum", "CProcessDescriptor",
                "CEventDescriptor", "CJails", "Jails",
                "CINotify", "CDeviceIoctl"
            ]
        ),
        .target(
            name: "Capabilities",
            dependencies: ["Capsicum", "CProcessDescriptor", "Descriptors"]
        ),
        .target(
            name: "SignalDispatchers",
            dependencies: ["Descriptors", "FreeBSDKit", "CSignal"]
        ),
        .target(
            name: "FPC",
            dependencies: ["Capabilities", "Descriptors", "Capsicum", "FreeBSDKit"],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "CapsicumTests",
            dependencies: ["Capsicum"]
        ),
        .testTarget(
            name: "CCapsicumTests",
            dependencies: ["CCapsicum"]
        ),
        .testTarget(
            name: "JailsTests",
            dependencies: ["Jails"]
        ),
        .testTarget(
            name: "CapabilitiesTests",
            dependencies: ["Capabilities"]
        ),
        .testTarget(
            name: "DescriptorsTests",
            dependencies: ["Capsicum", "CProcessDescriptor", "Descriptors"]
        ),
        .testTarget(
            name: "SignalDispatchersTests",
            dependencies: ["SignalDispatchers", "Descriptors", "FreeBSDKit"]
        ),
        .testTarget(
            name: "FreeBSDKitTests",
            dependencies: ["FreeBSDKit"]
        ),
        .testTarget(
            name: "FPCTests",
            dependencies: ["FPC", "Capabilities", "Descriptors"]
        ),
        .target(
            name: "MacLabel",
            dependencies: ["FreeBSDKit", "Capabilities", "Descriptors"],
            exclude: ["README.md"]
        ),
        .target(
            name: "CMacLabelParser",
            path: "Sources/CMacLabelParser",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "MacLabelTests",
            dependencies: ["MacLabel"]
        ),
        .testTarget(
            name: "CasperTests",
            dependencies: ["Casper", "Capsicum"]
        ),
        .testTarget(
            name: "ProcctlTests",
            dependencies: ["Procctl"]
        ),
        .testTarget(
            name: "ACLTests",
            dependencies: ["ACL", "Capabilities"]
        ),
        .testTarget(
            name: "RctlTests",
            dependencies: ["Rctl"]
        ),
        .testTarget(
            name: "CpusetTests",
            dependencies: ["Cpuset"]
        ),
        .testTarget(
            name: "AuditTests",
            dependencies: ["Audit"]
        ),
        .testTarget(
            name: "CAuditTests",
            dependencies: ["CAudit"]
        ),
        .target(
            name: "CDTrace",
            path: "Sources/CDTrace",
            linkerSettings: [
                .linkedLibrary("dtrace")
            ]
        ),
        .target(
            name: "DTraceCore",
            dependencies: ["CDTrace"]
        ),
        .target(
            name: "DBlocks",
            dependencies: ["DTraceCore", "FreeBSDKit"]
        ),
        .testTarget(
            name: "DTraceCoreTests",
            dependencies: ["DTraceCore"]
        ),
        .testTarget(
            name: "DBlocksTests",
            dependencies: ["DBlocks", "Descriptors", "Capabilities"]
        ),
        .target(
            name: "AgeSignal",
            dependencies: ["FreeBSDKit", "FPC", "Descriptors", "Capabilities"]
        ),
        .target(
            name: "Netmap",
            dependencies: ["CNetmap", "FreeBSDKit"]
        ),
        .testTarget(
            name: "AgeSignalTests",
            dependencies: ["AgeSignal"]
        ),
        .testTarget(
            name: "NetmapTests",
            dependencies: ["Netmap"]
        ),
        .executableTarget(
            name: "maclabel",
            dependencies: [
                "MacLabel",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/mac-policy-cli",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "fpc-demo",
            dependencies: ["FPC", "Capabilities", "Descriptors"],
            path: "Examples/FPCDemo",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "acl-demo",
            dependencies: ["ACL"],
            path: "Examples/ACLDemo"
        ),
        .executableTarget(
            name: "dprobes-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dprobes-cli"
        ),
        .executableTarget(
            name: "dblocks-examples",
            dependencies: ["DBlocks"],
            path: "Examples/DBlocksExamples"
        ),
        .testTarget(
            name: "DProbesCLITests",
            dependencies: ["dprobes-cli"]
        ),
        .executableTarget(
            name: "aged",
            dependencies: [
                "AgeSignal",
                "FPC",
                "FreeBSDKit",
                "Capsicum",
                "Casper",
                "Capabilities",
                "Descriptors",
                "Audit",
                "SignalDispatchers",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/aged"
        ),
        .executableTarget(
            name: "agectl",
            dependencies: [
                "AgeSignal",
                "FPC",
                "Capsicum",
                "Casper",
                "Audit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/agectl"
        ),
        .executableTarget(
            name: "jails-demo",
            dependencies: ["Jails", "Descriptors"],
            path: "Examples/JailsDemo"
        ),
        .executableTarget(
            name: "kqueue-demo",
            dependencies: ["Capabilities", "Descriptors", "SignalDispatchers", "FreeBSDKit"],
            path: "Examples/KqueueDemo"
        ),
        .executableTarget(
            name: "netmap-demo",
            dependencies: ["Netmap", "FreeBSDKit"],
            path: "Examples/NetmapDemo"
        ),
    ]
)
