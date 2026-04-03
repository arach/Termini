// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localGhosttyKitRelativePath = "vendor/ghostty/macos/GhosttyKit.xcframework"
let localGhosttyKitAbsolutePath = packageRoot.appending(path: localGhosttyKitRelativePath).path
let bundledGhosttyKitExists = FileManager.default.fileExists(atPath: localGhosttyKitAbsolutePath)
let releaseGhosttyKitURL = "https://github.com/arach/TermBridgeKit/releases/download/0.1.1/GhosttyKit.xcframework.zip"
let releaseGhosttyKitChecksum = "c1cf5a0d58e6c2b6242ee92fcf75e4eac382e10979813c7c1970be90281101b6"

let ghosttyKitTarget: Target =
    if bundledGhosttyKitExists {
        .binaryTarget(
            name: "GhosttyKit",
            path: localGhosttyKitRelativePath
        )
    } else {
        .binaryTarget(
            name: "GhosttyKit",
            url: releaseGhosttyKitURL,
            checksum: releaseGhosttyKitChecksum
        )
    }

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
        ghosttyKitTarget,
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
