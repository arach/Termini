import Foundation
import GhosttyKit

public struct GhosttyVersion {
    public let version: String
    public let buildMode: String

    public init(info: ghostty_info_s = ghostty_info()) {
        let byteCount = Int(info.version_len)
        if byteCount > 0, let rawPtr = UnsafeRawPointer(info.version) {
            let buffer = UnsafeRawBufferPointer(start: rawPtr, count: byteCount)
            self.version = String(bytes: buffer, encoding: .utf8) ?? "unknown"
        } else {
            self.version = "unknown"
        }

        switch info.build_mode {
        case GHOSTTY_BUILD_MODE_DEBUG:
            buildMode = "debug"
        case GHOSTTY_BUILD_MODE_RELEASE_SAFE:
            buildMode = "release-safe"
        case GHOSTTY_BUILD_MODE_RELEASE_FAST:
            buildMode = "release-fast"
        case GHOSTTY_BUILD_MODE_RELEASE_SMALL:
            buildMode = "release-small"
        default:
            buildMode = "unknown"
        }
    }
}
