// swift-tools-version: 5.9
import Foundation
import PackageDescription

let fileManager = FileManager.default
let packageRootCandidates = [
    URL(fileURLWithPath: fileManager.currentDirectoryPath),
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
]
let packageRoot = packageRootCandidates.first(where: {
    fileManager.fileExists(atPath: $0.appending(path: "Package.swift").path)
}) ?? packageRootCandidates[0]
let localGhosttyKitRelativePath = "vendor/ghostty/macos/GhosttyKit.xcframework"
let localGhosttyKitAbsolutePath = packageRoot.appending(path: localGhosttyKitRelativePath).path
let bundledGhosttyKitExists = fileManager.fileExists(atPath: localGhosttyKitAbsolutePath)
let releaseGhosttyKitURL = "https://github.com/arach/TermBridgeKit/releases/download/0.1.2/GhosttyKit.xcframework.zip"
let releaseGhosttyKitChecksum = "a1e30beb0e4423e875a11264ce36e4639b0d08b9a1e0f3c456e87971962eb577"

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
