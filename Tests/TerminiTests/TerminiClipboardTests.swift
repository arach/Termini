#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import Termini

final class TerminiClipboardTests: XCTestCase {
    @MainActor private static var retainedFixtures: [(NSView, NSWindow)] = []

    @MainActor
    func testOSC52WritesTextToSystemClipboard() async throws {
        _ = NSApplication.shared
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        defer {
            snapshot.restore(to: pasteboard)
        }

        let controller = TerminiTerminalController()
        let terminalView = TerminiTerminalView(
            controller: controller,
            showsSystemKeyboard: false
        )
        let hostingView = NSHostingView(rootView: terminalView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let expectedClipboard = "termini-osc52-\(UUID().uuidString)"
        let encodedClipboard = Data(expectedClipboard.utf8).base64EncodedString()
        controller.processRemoteOutput(
            Data("\u{1B}]52;c;\(encodedClipboard)\u{07}".utf8)
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while pasteboard.string(forType: .string) != expectedClipboard,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(
            pasteboard.string(forType: .string) == expectedClipboard,
            "OSC 52 did not update the system clipboard."
        )
        Self.retainedFixtures.append((hostingView, window))
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let pasteboardItems = items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }
}
#endif
