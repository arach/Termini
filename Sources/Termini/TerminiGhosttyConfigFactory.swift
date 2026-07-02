import Foundation
import GhosttyKit

enum TerminiGhosttyConfigFactory {
    static func makeConfig(
        baseConfig: ghostty_config_t?,
        appearance: TerminiTerminalAppearance
    ) -> ghostty_config_t? {
        guard let baseConfig, let config = ghostty_config_clone(baseConfig) else {
            return nil
        }

        var modified = false

        if let fontSize = appearance.clampedGhosttyFontSize {
            ghostty_config_set_font_size(config, Float(fontSize))
            modified = true
        }

        if let fontFamily = appearance.normalizedFontFamilyName {
            let didSetFamily = fontFamily.withCString { value in
                ghostty_config_set_font_family(config, value, UInt(fontFamily.utf8.count))
            }

            guard didSetFamily else {
                ghostty_config_free(config)
                return nil
            }
            modified = true
        }

        // Load extra config files (e.g. a host app's colour theme snippet). The
        // C API exposes no per-key colour setter, so colours come in this way.
        for path in appearance.extraConfigFilePaths {
            path.withCString { ghostty_config_load_file(config, $0) }
            modified = true
        }

        if modified {
            ghostty_config_finalize(config)
        }

        return config
    }
}

extension TerminiTerminalAppearance {
    var clampedGhosttyFontSize: Double? {
        fontSize.map { min(max($0, 1), 255) }
    }

    var normalizedFontFamilyName: String? {
        guard let fontFamily else { return nil }
        let trimmed = fontFamily.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasRuntimeFontOverride: Bool {
        clampedGhosttyFontSize != nil || normalizedFontFamilyName != nil
    }
}
