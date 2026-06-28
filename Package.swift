// swift-tools-version: 5.9
import Foundation
import PackageDescription

let fileManager = FileManager.default
// Prefer the directory containing *this* Package.swift so the local-vendor
// preference works the same way whether Termini is built directly or as a
// SwiftPM dependency of another package (where PWD/cwd point at the
// consumer, not Termini).
let packageRootCandidates = [
    URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
    ProcessInfo.processInfo.environment["PWD"].map(URL.init(fileURLWithPath:)),
    URL(fileURLWithPath: fileManager.currentDirectoryPath),
].compactMap { $0 }
let packageRoot = packageRootCandidates.first(where: {
    fileManager.fileExists(atPath: $0.appending(path: "Package.swift").path)
}) ?? packageRootCandidates[0]
let localGhosttyKitRelativePath = "vendor/ghostty/macos/GhosttyKit.xcframework"
let localGhosttyKitAbsolutePath = packageRoot.appending(path: localGhosttyKitRelativePath).path
let bundledGhosttyKitExists = fileManager.fileExists(atPath: localGhosttyKitAbsolutePath)
// 0.1.6 tracks Ghostty main (07d31666e, Jun 2026) plus Termini embedding
// APIs (`write_to_host_cb`, `ghostty_surface_process_output`, font config
// setters). Upstream already includes the iOS Metal surface-attach fixes.
//
// Local development: drop the rebuilt xcframework into
// `vendor/ghostty/macos/GhosttyKit.xcframework` and the local-vendor
// preference above will use it. The URL below is consumed when no local
// vendor is present (CI, downstream packages).
let releaseGhosttyKitURL = "https://github.com/arach/TermBridgeKit/releases/download/0.1.6/GhosttyKit.xcframework.zip"
let releaseGhosttyKitChecksum = "7265c68e6e2120d8e3ed9bd9299177f6de9312fde492f7923e2af67b23ba1339"

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
    name: "Termini",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Termini",
            targets: ["Termini"]
        ),
        .library(
            name: "TerminiSSH",
            targets: ["TerminiSSH"]
        ),
        .executable(
            name: "TerminiDemo",
            targets: ["TerminiDemo"]
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
            name: "Termini",
            dependencies: [
                "GhosttyKit"
            ],
            linkerSettings: terminalLinkerSettings
        ),
        .target(
            name: "TerminiSSH",
            dependencies: [
                "Termini",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
            ]
        ),
        .executableTarget(
            name: "TerminiDemo",
            dependencies: ["Termini"],
            path: "Examples/TerminiDemo"
        ),
        .testTarget(
            name: "TerminiTests",
            dependencies: ["Termini"]
        ),
        .testTarget(
            name: "TerminiSSHTests",
            dependencies: [
                "TerminiSSH",
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ]
        )
    ]
)
