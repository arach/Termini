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

        // Runtime font customization (`ghostty_config_set_font_*`) is gated on
        // GhosttyKit 0.1.3+. We currently pin to 0.1.2 because 0.1.3 has an
        // iOS surface-attach regression. When 0.1.4 (or a fixed 0.1.3) lands,
        // re-enable these calls — `appearance.fontSize` / `.fontFamily` are
        // currently dropped on the floor, so callers get whatever the base
        // ghostty config compiled in.
        _ = appearance.clampedGhosttyFontSize
        _ = appearance.normalizedFontFamilyName

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
