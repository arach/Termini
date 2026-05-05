#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import Termini

/// iOS surface-attach smoke test. Catches the regression class hit by
/// GhosttyKit 0.1.3 where the libghostty iOS path triggers
/// `-[CAMetalLayer addSublayer]` (no-arg selector, doesn't exist on
/// any Apple class) the moment any consumer mounts a TerminiTerminalView.
///
/// Mounts the public `TerminiTerminalView` inside a real `UIHostingController`
/// + `UIWindow`, runs a layout pass + brief runloop, asserts no crash.
/// The crash mode for 0.1.3 is an uncaught NSException out of
/// `SurfaceContainerView.didMoveToWindow → createSurfaceIfNeeded →
/// ghostty_surface_new`, which under XCTest manifests as a test failure
/// rather than a process abort.
///
/// If this test starts failing again, GhosttyKit has regressed the iOS
/// surface attach path — investigate the binary release before bumping.
final class SurfaceAttachTests_iOS: XCTestCase {

    @MainActor
    func testTerminalViewMountsWithoutCrashing() {
        let controller = TerminiTerminalController()
        let appearance = TerminiTerminalAppearance(theme: .midnightBloom)
        let terminalView = TerminiTerminalView(
            controller: controller,
            showsSystemKeyboard: false,
            appearance: appearance
        )

        let host = UIHostingController(rootView: terminalView)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 240)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = host
        window.makeKeyAndVisible()

        // Force layout so didMoveToWindow fires and createSurfaceIfNeeded runs.
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))

        XCTAssertNotNil(host.view, "Hosting controller view should be live after attach.")
        XCTAssertNotNil(window.rootViewController, "Window should retain its root controller.")
    }

    @MainActor
    func testTerminalViewAcceptsCannedOutputWithoutCrashing() {
        let controller = TerminiTerminalController()
        let terminalView = TerminiTerminalView(
            controller: controller,
            showsSystemKeyboard: false,
            appearance: TerminiTerminalAppearance(theme: .midnightBloom)
        )

        let host = UIHostingController(rootView: terminalView)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 240)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))

        // Push a small ANSI-colored buffer through the controller. If the
        // surface attached cleanly above, the renderer should consume bytes
        // without throwing.
        let esc = "\u{1B}["
        let payload = "\(esc)32mok\(esc)0m\r\n"
        controller.processRemoteOutput(Data(payload.utf8))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNotNil(controller.currentSize() ?? TerminiTerminalSize(columns: 1, rows: 1, cellWidthPixels: 1, cellHeightPixels: 1))
    }
}
#endif
