import XCTest
import GhosttyKit
@testable import Termini

final class TerminiOpenURLActionTests: XCTestCase {
    func testHandleOpensExplicitURL() {
        withAction("https://github.com/arach/Termini/pull/13") { action in
            var openedURL: URL?

            let handled = TerminiOpenURLAction.handle(action) { url in
                openedURL = url
                return true
            }

            XCTAssertTrue(handled)
            XCTAssertEqual(openedURL?.absoluteString, "https://github.com/arach/Termini/pull/13")
        }
    }

    func testHandleUsesOnlyReportedByteLength() {
        let expected = "https://example.com"

        withAction("\(expected)/ignored", length: expected.utf8.count) { action in
            let url = TerminiOpenURLAction.url(from: action)

            XCTAssertEqual(url?.absoluteString, expected)
        }
    }

    func testHandleConvertsPathToFileURL() {
        withAction("~/Documents/session.log") { action in
            let url = TerminiOpenURLAction.url(from: action)

            XCTAssertTrue(url?.isFileURL == true)
            XCTAssertEqual(url?.lastPathComponent, "session.log")
        }
    }

    func testHandleRejectsMissingURL() {
        let action = ghostty_action_open_url_s(
            kind: GHOSTTY_ACTION_OPEN_URL_KIND_UNKNOWN,
            url: nil,
            len: 0
        )

        XCTAssertFalse(TerminiOpenURLAction.handle(action) { _ in true })
    }

    func testHandleRejectsInvalidUTF8() {
        let bytes: [UInt8] = [0xFF]

        bytes.withUnsafeBytes { buffer in
            let action = ghostty_action_open_url_s(
                kind: GHOSTTY_ACTION_OPEN_URL_KIND_UNKNOWN,
                url: buffer.bindMemory(to: CChar.self).baseAddress,
                len: UInt(bytes.count)
            )

            XCTAssertFalse(TerminiOpenURLAction.handle(action) { _ in true })
        }
    }

    private func withAction(
        _ value: String,
        length: Int? = nil,
        perform: (ghostty_action_open_url_s) -> Void
    ) {
        let bytes = Array(value.utf8)

        bytes.withUnsafeBytes { buffer in
            let action = ghostty_action_open_url_s(
                kind: GHOSTTY_ACTION_OPEN_URL_KIND_UNKNOWN,
                url: buffer.bindMemory(to: CChar.self).baseAddress,
                len: UInt(length ?? bytes.count)
            )

            perform(action)
        }
    }
}
