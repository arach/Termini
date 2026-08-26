#if canImport(AppKit)
import XCTest
@testable import Termini

final class TerminiMouseButtonSequenceTests: XCTestCase {
    func testUpdatesPositionBeforeSendingButton() {
        var events: [String] = []

        TerminiMouseButtonSequence.perform(
            updatePosition: { events.append("position") },
            sendButton: { events.append("button") }
        )

        XCTAssertEqual(events, ["position", "button"])
    }
}
#endif
