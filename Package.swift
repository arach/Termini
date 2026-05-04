// swift-tools-version: 5.9
import Foundation
import PackageDescription

let fileManager = FileManager.default
let packageRootCandidates = [
    ProcessInfo.processInfo.environment["PWD"].map(URL.init(fileURLWithPath:)),
    URL(fileURLWithPath: fileManager.currentDirectoryPath),
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
].compactMap { $0 }
let packageRoot = packageRootCandidates.first(where: {
    fileManager.fileExists(atPath: $0.appending(path: "Package.swift").path)
}) ?? packageRootCandidates[0]
let localGhosttyKitRelativePath = "vendor/ghostty/macos/GhosttyKit.xcframework"
let localGhosttyKitAbsolutePath = packageRoot.appending(path: localGhosttyKitRelativePath).path
let bundledGhosttyKitExists = fileManager.fileExists(atPath: localGhosttyKitAbsolutePath)
let releaseGhosttyKitURL = "https://github.com/arach/TermBridgeKit/releases/download/0.1.3/GhosttyKit.xcframework.zip"
let releaseGhosttyKitChecksum = "254f901b8fd1374791d5155bb0280d0b32addf54d477fcccbaafed418fee4bb3"

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

let terminalLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
    .linkedFramework("AppKit", .when(platforms: [.macOS])),
    .linkedFramework("Carbon", .when(platforms: [.macOS])),
    .linkedFramework("CoreGraphics"),
    .linkedFramework("CoreText"),
    .linkedFramework("Metal"),
    .linkedFramework("UIKit", .when(platforms: [.iOS])),
    .linkedFramework("QuartzCore", .when(platforms: [.iOS]))
]

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
        .library(
            name: "TermBridgeKitSSH",
            targets: ["TermBridgeKitSSH"]
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
                "GhosttyKit"
            ],
            linkerSettings: terminalLinkerSettings
        ),
        .target(
            name: "TermBridgeKitSSH",
            dependencies: [
                "TermBridgeKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
            ]
        ),
        .executableTarget(
            name: "TermBridgeKitDemo",
            dependencies: ["TermBridgeKit"],
            path: "Examples/TermBridgeKitDemo"
        ),
        .testTarget(
            name: "TermBridgeKitTests",
            dependencies: ["TermBridgeKit"]
        ),
        .testTarget(
            name: "TermBridgeKitSSHTests",
            dependencies: [
                "TermBridgeKitSSH",
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ]
        )
    ]
)
