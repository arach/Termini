// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TermBridgeKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TermBridgeKit",
            targets: ["TermBridgeKit"]
        ),
        .executable(
            name: "TermBridgeKitDemo",
            targets: ["TermBridgeKitDemo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.97.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.1"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.26.0")
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "vendor/ghostty/macos/GhosttyKit.xcframework"
        ),
        .target(
            name: "TermBridgeKit",
            dependencies: [
                "GhosttyKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Metal"),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.iOS]))
            ]
        ),
        .executableTarget(
            name: "TermBridgeKitDemo",
            dependencies: ["TermBridgeKit"],
            path: "Examples/TermBridgeKitDemo"
        ),
        .testTarget(
            name: "TermBridgeKitTests",
            dependencies: [
                "TermBridgeKit",
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ]
        )
    ]
)
