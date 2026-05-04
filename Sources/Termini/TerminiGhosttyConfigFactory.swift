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

        if let fontSize = appearance.clampedGhosttyFontSize {
            ghostty_config_set_font_size(config, Float(fontSize))
        }

        if let fontFamily = appearance.normalizedFontFamilyName {
            let didSetFamily = fontFamily.withCString { value in
                ghostty_config_set_font_family(config, value, UInt(fontFamily.utf8.count))
            }

            guard didSetFamily else {
                ghostty_config_free(config)
                return nil
            }

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
