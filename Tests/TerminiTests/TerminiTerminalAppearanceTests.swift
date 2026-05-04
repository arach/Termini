import XCTest
import GhosttyKit
@testable import Termini

final class TerminiTerminalAppearanceTests: XCTestCase {
    private enum GhosttyTestBootstrap {
        static let initializeResult: Int32 = ghostty_init(0, nil)
    }

    private func makeBaseConfig() -> ghostty_config_t {
        XCTAssertEqual(GhosttyTestBootstrap.initializeResult, GHOSTTY_SUCCESS)
        guard let config = ghostty_config_new() else {
            XCTFail("Expected a Ghostty config.")
            fatalError("Ghostty config unavailable")
        }
        ghostty_config_finalize(config)
        return config
    }

    private func fontSize(from config: ghostty_config_t?) -> Float {
        var fontSize: Float = 0
        let success = ghostty_config_get(config, &fontSize, "font-size", UInt("font-size".utf8.count))
        XCTAssertTrue(success)
        return fontSize
    }

    // GhosttyKit 0.1.3+ API. Currently pinned to 0.1.2 due to iOS surface
    // regression; restore when fix lands.
    #if false
    private func fontFamilies(from config: ghostty_config_t?) -> [String] {
        let count = Int(ghostty_config_font_family_count(config))
        return (0..<count).compactMap { index in
            guard let value = ghostty_config_font_family_get(config, UInt32(index)) else {
                return nil
            }
            return String(cString: value)
        }
    }
    #endif

    func testPresetThemesShipWithCompleteAnsiPalettes() {
        for theme in TerminiTerminalTheme.presets {
            XCTAssertEqual(theme.ansiPalette.count, 16, "\(theme.name) should expose a full ANSI palette.")
        }
    }

    func testApplyEscapeSequenceIncludesCoreDynamicColorsAndAnsiPalette() {
        let theme = TerminiTerminalTheme.midnightBloom
        let sequence = theme.applyEscapeSequence

        XCTAssertTrue(sequence.contains("\u{1B}]10;rgb:E6E6/EDED/F7F7\u{07}"))
        XCTAssertTrue(sequence.contains("\u{1B}]11;rgb:0D0D/1313/2121\u{07}"))
        XCTAssertTrue(sequence.contains("\u{1B}]12;rgb:FFFF/8A8A/5B5B\u{07}"))
        XCTAssertTrue(sequence.contains("\u{1B}]4;15;rgb:FFFF/FFFF/FFFF\u{07}"))
    }

    func testResetEscapeSequenceResetsDynamicColorsAndPalette() {
        XCTAssertEqual(
            TerminiTerminalTheme.resetEscapeSequence,
            "\u{1B}]104\u{07}\u{1B}]110\u{07}\u{1B}]111\u{07}\u{1B}]112\u{07}\u{1B}]117\u{07}\u{1B}]119\u{07}"
        )
    }

    // GhosttyKit 0.1.3+ APIs (set_font_size, set_font_family,
    // font_family_count/get) gated below — currently pinned to 0.1.2.
    #if false
    func testConfigFactoryAppliesFontSizeAndFontFamilyOverrides() {
        let baseConfig = makeBaseConfig()
        defer { ghostty_config_free(baseConfig) }

        let config = TerminiGhosttyConfigFactory.makeConfig(
            baseConfig: baseConfig,
            appearance: .init(
                fontSize: 18,
                fontFamily: .init(name: "SF Mono")
            )
        )
        defer { ghostty_config_free(config) }

        XCTAssertEqual(fontSize(from: config), 18)
        XCTAssertEqual(fontFamilies(from: config), ["SF Mono"])
    }

    func testConfigFactoryResetsToAmbientFontValuesWhenOverridesAreRemoved() {
        let baseConfig = makeBaseConfig()
        defer { ghostty_config_free(baseConfig) }

        ghostty_config_set_font_size(baseConfig, 15)
        _ = "JetBrains Mono".withCString { value in
            ghostty_config_set_font_family(baseConfig, value, UInt("JetBrains Mono".utf8.count))
        }
        ghostty_config_finalize(baseConfig)

        let customConfig = TerminiGhosttyConfigFactory.makeConfig(
            baseConfig: baseConfig,
            appearance: .init(
                fontSize: 20,
                fontFamily: .init(name: "SF Mono")
            )
        )
        defer { ghostty_config_free(customConfig) }

        XCTAssertEqual(fontSize(from: customConfig), 20)
        XCTAssertEqual(fontFamilies(from: customConfig), ["SF Mono"])

        let ambientConfig = TerminiGhosttyConfigFactory.makeConfig(
            baseConfig: baseConfig,
            appearance: .default
        )
        defer { ghostty_config_free(ambientConfig) }

        XCTAssertEqual(fontSize(from: ambientConfig), 15)
        XCTAssertEqual(fontFamilies(from: ambientConfig), ["JetBrains Mono"])
    }

    func testConfigFactoryTrimsWhitespaceOnlyFontFamilyOverrides() {
        let baseConfig = makeBaseConfig()
        defer { ghostty_config_free(baseConfig) }

        let config = TerminiGhosttyConfigFactory.makeConfig(
            baseConfig: baseConfig,
            appearance: .init(fontFamily: .init(name: "   "))
        )
        defer { ghostty_config_free(config) }

        XCTAssertEqual(fontFamilies(from: config), [])
    }
    #endif
}
