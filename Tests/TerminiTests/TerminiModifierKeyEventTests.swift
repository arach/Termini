#if canImport(AppKit)
import AppKit
import GhosttyKit
import XCTest
@testable import Termini

final class TerminiModifierKeyEventTests: XCTestCase {
    func testCommandPressUsesPressAction() {
        XCTAssertEqual(
            TerminiModifierKeyEvent.action(
                keyCode: 55,
                modifierFlags: [.command]
            ),
            GHOSTTY_ACTION_PRESS
        )
    }

    func testCommandReleaseUsesReleaseAction() {
        XCTAssertEqual(
            TerminiModifierKeyEvent.action(
                keyCode: 55,
                modifierFlags: []
            ),
            GHOSTTY_ACTION_RELEASE
        )
    }

    func testRightCommandUsesCommandFlag() {
        XCTAssertEqual(
            TerminiModifierKeyEvent.action(
                keyCode: 54,
                modifierFlags: [.command]
            ),
            GHOSTTY_ACTION_PRESS
        )
    }

    func testModifierChangeDoesNotReadKeyCharacters() {
        XCTAssertFalse(TerminiKeyEventText.canReadCharacters(from: .flagsChanged))
    }

    func testKeyDownCanReadKeyCharacters() {
        XCTAssertTrue(TerminiKeyEventText.canReadCharacters(from: .keyDown))
    }
}
#endif
