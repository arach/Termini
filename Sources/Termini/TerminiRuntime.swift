#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import GhosttyKit

/// Minimal wrapper around libghostty runtime so we can create surfaces and tick the engine.
@MainActor
final class TerminiRuntime: ObservableObject {
    static let shared = TerminiRuntime()

    private let config: ghostty_config_t?
    private(set) var app: ghostty_app_t?

    /// Backstop timer in case the runtime doesn’t wake us up (see startTickLoop).
    private var tickTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var hasPendingWakeupTick = false
    private let debugInputLogging = ProcessInfo.processInfo.environment["TERMBRIDGEKIT_DEBUG_INPUT"] == "1"

    private init() {
        #if canImport(AppKit)
        // SPM executables default to `.prohibited`, which blocks keyboard focus.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if debugInputLogging {
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                NSLog("[TerminiRuntime] global monitor saw \(event.type == .keyDown ? "down" : "up") keyCode=\(event.keyCode) mods=0x\(String(event.modifierFlags.rawValue, radix: 16)) windowKey=\(event.window?.isKeyWindow == true) appActive=\(NSApp.isActive)")
                return event
            }
        }
        #endif

        // libghostty requires global init prior to any other calls.
        let initResult = ghostty_init(0, nil)
        guard initResult == GHOSTTY_SUCCESS else {
            assertionFailure("ghostty_init failed with code \(initResult)")
            self.config = nil
            return
        }

        // Prepare configuration with defaults.
        self.config = ghostty_config_new()
        guard let config else {
            return
        }

        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        // Build runtime callbacks.
        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in
                TerminiRuntime.wakeup(userdata)
            },
            action_cb: { app, target, action in
                TerminiRuntime.handleAction(app: app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                TerminiRuntime.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, string, state, _ in
                TerminiRuntime.confirmReadClipboard(userdata, string: string, state: state)
            },
            write_clipboard_cb: { _, _, _, _, _ in
            },
            write_to_host_cb: { surfaceUserdata, bytes, count in
                TerminiRuntime.writeToHost(surfaceUserdata, bytes, count)
            },
            close_surface_cb: { _, _ in
            }
        )

        // Create the Ghostty app.
        self.app = ghostty_app_new(&runtime, config)
        if let app {
            #if canImport(AppKit)
            ghostty_app_set_focus(app, NSApp.isActive)
            #else
            ghostty_app_set_focus(app, true)
            #endif
        }

        // Kick off a gentle tick loop so background work proceeds.
        startTickLoop()

        #if canImport(AppKit)
        // Bring our app forward so keystrokes go to the window when launched via `swift run`.
        NSApp.activate(ignoringOtherApps: true)
        #endif
        observeAppFocus()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        tickTimer?.invalidate()
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    // MARK: - Callbacks

    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let runtime = Unmanaged<TerminiRuntime>.fromOpaque(userdata).takeUnretainedValue()
        Task { @MainActor in
            runtime.scheduleWakeupTick()
        }
    }

    private static func handleAction(
        app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        // For now we acknowledge all actions without special handling.
        return true
    }

    private static func surfaceView(
        from userdata: UnsafeMutableRawPointer?
    ) -> SurfaceContainerView? {
        guard let userdata else { return nil }
        return Unmanaged<SurfaceContainerView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        #if canImport(AppKit)
        guard let view = surfaceView(from: userdata) else { return false }
        return view.readClipboard(location: location, state: state)
        #else
        return false
        #endif
    }

    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?
    ) {
        #if canImport(AppKit)
        guard let view = surfaceView(from: userdata),
              let string else { return }
        view.completeClipboardRequest(String(cString: string), state: state, confirmed: true)
        #endif
    }

    private static func writeToHost(
        _ surfaceUserdata: UnsafeMutableRawPointer?,
        _ bytes: UnsafePointer<UInt8>?,
        _ count: Int
    ) {
        guard let surfaceUserdata, let bytes, count > 0 else { return }
        let data = Data(bytes: bytes, count: count)
        // Use GCD instead of Task { @MainActor } — lower overhead for rapid key repeat.
        DispatchQueue.main.async {
            let view = Unmanaged<SurfaceContainerView>
                .fromOpaque(surfaceUserdata)
                .takeUnretainedValue()
            view.handleTransportWrite(data)
        }
    }

    // MARK: - Ticking

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func scheduleWakeupTick() {
        guard !hasPendingWakeupTick else { return }
        hasPendingWakeupTick = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingWakeupTick = false
            self.tick()
        }
    }

    // The tick loop is a slow backstop, not a 60 Hz drive. Real work is pushed
    // through `wakeup_cb` → `scheduleWakeupTick()`: libghostty asks for a tick
    // whenever its mailbox has messages, so ticking blindly at 60 Hz just
    // burned 60 wakeups + 60 main-queue dispatches per second forever
    // (blocking App Nap and draining battery while the app sat idle). Keep a
    // once-a-second safety net with wide tolerance so a missed wakeup can never
    // wedge the engine, and let the OS coalesce the wakeup with other timers.
    private func startTickLoop() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        timer.tolerance = 0.5
        tickTimer = timer
    }

    private func observeAppFocus() {
        let center = NotificationCenter.default
        #if canImport(AppKit)
        let become = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let app = self.app else { return }
                ghostty_app_set_focus(app, true)
            }
        }
        let resign = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let app = self.app else { return }
                ghostty_app_set_focus(app, false)
            }
        }
        notificationTokens.append(contentsOf: [become, resign])
        #elseif canImport(UIKit)
        let become = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let app = self.app else { return }
                ghostty_app_set_focus(app, true)
            }
        }
        let resign = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let app = self.app else { return }
                ghostty_app_set_focus(app, false)
            }
        }
        notificationTokens.append(contentsOf: [become, resign])
        #endif
    }

    func keyboardDidChange() {
        guard let app else { return }
        ghostty_app_keyboard_changed(app)
    }

    func makeSurfaceConfig(for appearance: TerminiTerminalAppearance) -> ghostty_config_t? {
        TerminiGhosttyConfigFactory.makeConfig(
            baseConfig: config,
            appearance: appearance
        )
    }

}
