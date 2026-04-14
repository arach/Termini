import XCTest
@testable import TermBridgeKit

final class TermBridgeKitTerminalAppearanceTests: XCTestCase {
    func testPresetThemesShipWithCompleteAnsiPalettes() {
        for theme in TermBridgeKitTerminalTheme.presets {
            XCTAssertEqual(theme.ansiPalette.count, 16, "\(theme.name) should expose a full ANSI palette.")
        }
    }

    func testApplyEscapeSequenceIncludesCoreDynamicColorsAndAnsiPalette() {
        let theme = TermBridgeKitTerminalTheme.midnightBloom
        let sequence = theme.applyEscapeSequence

        XCTAssertTrue(sequence.contains("\u{1B}]10;rgb:E6E6/EDED/F7F7\u{07}"))
        XCTAssertTrue(sequence.contains("\u{1B}]11;rgb:0D0D/1313/2121\u{07}"))
        XCTAssertTrue(sequence.contains("\u{1B}]12;rgb:FFFF/8A8A/5B5B\u{07}"))
        XCTAssertTrue(sequence.contains("\u{1B}]4;15;rgb:FFFF/FFFF/FFFF\u{07}"))
    }

    func testResetEscapeSequenceResetsDynamicColorsAndPalette() {
        XCTAssertEqual(
            TermBridgeKitTerminalTheme.resetEscapeSequence,
            "\u{1B}]104\u{07}\u{1B}]110\u{07}\u{1B}]111\u{07}\u{1B}]112\u{07}\u{1B}]117\u{07}\u{1B}]119\u{07}"
        )
    }
}
