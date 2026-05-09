// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MyFreeBSDApp",
    dependencies: [
        .package(url: "https://github.com/SwiftBSD/FreeBSDKit", from: "0.2.6")
    ],
    targets: [
        .executableTarget(
            name: "MyFreeBSDApp",
            dependencies: [
                .product(name: "FreeBSDKit", package: "FreeBSDKit"),
                .product(name: "Capsicum", package: "FreeBSDKit"),
                .product(name: "Capabilities", package: "FreeBSDKit"),
                .product(name: "Descriptors", package: "FreeBSDKit"),
                .product(name: "Jails", package: "FreeBSDKit")
            ]
        )
    ]
)
