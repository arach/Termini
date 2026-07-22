#if canImport(AppKit)

import AppKit
import SwiftUI
import GhosttyKit

/// SwiftUI wrapper that embeds the live Ghostty surface.
public struct TerminiSurfaceView: NSViewRepresentable {
    private let controller: TerminiTerminalController?
    private let showsSystemKeyboard: Bool
    private let appearance: TerminiTerminalAppearance
    // hosts that keep several surfaces mounted (warm caches)
    // mark all but the selected one invisible so hidden surfaces stop drawing.
    private let isRenderVisible: Bool

    public init(
        controller: TerminiTerminalController? = nil,
        showsSystemKeyboard: Bool = true,
        appearance: TerminiTerminalAppearance = .default,
        isRenderVisible: Bool = true
    ) {
        self.controller = controller
        self.showsSystemKeyboard = showsSystemKeyboard
        self.appearance = appearance
        self.isRenderVisible = isRenderVisible
    }

    public init(
        controller: TerminiTerminalController? = nil,
        showsSystemKeyboard: Bool = true,
        fontSize: Double? = nil
    ) {
        self.init(
            controller: controller,
            showsSystemKeyboard: showsSystemKeyboard,
            appearance: .init(fontSize: fontSize)
        )
    }

    public func makeNSView(context: Context) -> SurfaceContainerView {
        let view = SurfaceContainerView(runtime: .shared)
        view.terminalAppearance = appearance
        view.isRenderVisible = isRenderVisible
        view.bind(controller: controller)
        return view
    }

    public func updateNSView(_ nsView: SurfaceContainerView, context: Context) {
        nsView.terminalAppearance = appearance
        nsView.isRenderVisible = isRenderVisible
        nsView.bind(controller: controller)
    }
}

/// NSView subclass that holds the Ghostty surface and forwards basic input.
public final class SurfaceContainerView: NSView {
    private let runtime: TerminiRuntime
    private var surface: ghostty_surface_t?
    private var surfaceCreationScheduled = false
    /// Set once the surface has been created and ticked. Until then, terminal
    /// output (theme escapes, early PTY bytes) is buffered rather than handed to
    /// `ghostty_surface_process_output`, which blocks the main thread on an
    /// un-ticked surface (the tick that drains it also runs on the main thread).
    private var surfaceIOReady = false
    private var pendingOutput = Data()
    private var renderTimer: Timer?
    private var renderTimerMode: RenderTimerMode?
    private var renderBurstDeadline = Date.distantPast
    private var trackingArea: NSTrackingArea?
    private var keyMonitor: Any?
    private weak var controller: TerminiTerminalController?
    private var lastReportedSize: TerminiTerminalSize?
    // MARK: coalesces PTY winsize pushes during live resize.
    private var pendingWinsizeReport: DispatchWorkItem?
    private let liveResizeWinsizeInterval: TimeInterval = 1.0 / 12.0
    private var lastAppliedAppearance: TerminiTerminalAppearance = .default
    private let debugInputLogging = ProcessInfo.processInfo.environment["TERMBRIDGEKIT_DEBUG_INPUT"] == "1"
    private var lastMouseLog: TimeInterval = 0
    private let mouseLogInterval: TimeInterval = 0.05
    private let activeRenderInterval: TimeInterval = 1.0 / 30.0
    private let idleFocusedRenderInterval: TimeInterval = 0.5
    // MARK: render/visibility gating (battery).
    // A surface that can't be seen must not draw: no render timers, no
    // per-output-chunk draws, and libghostty told via set_occlusion so its
    // renderer idles too. Output is still *processed* (terminal state stays
    // warm); one catch-up draw runs when the surface becomes visible again.
    /// Whether the SwiftUI host considers this surface visible (e.g. the
    /// selected surface of a warm cache). Set via `TerminiSurfaceView`.
    var isRenderVisible: Bool = true {
        didSet {
            guard oldValue != isRenderVisible else { return }
            renderGateChanged()
        }
    }
    /// Whether the hosting window is actually on screen (occlusion state).
    private var windowIsVisible = true
    /// Output arrived while gated; draw once on reveal.
    private var needsDrawOnReveal = false
    private var occlusionObserver: NSObjectProtocol?
    /// Immediate (non-timer) output draws are capped at ~60 fps; the active
    /// render burst timer coalesces the rest.
    private var lastOutputDraw: TimeInterval = 0
    private let minOutputDrawInterval: TimeInterval = 1.0 / 60.0

    private var canRender: Bool {
        isRenderVisible && windowIsVisible && window != nil && surface != nil
    }
    var terminalAppearance: TerminiTerminalAppearance = .default {
        didSet {
            guard oldValue != terminalAppearance else { return }
            updateBackgroundColor()
            applyTerminalAppearanceIfNeeded(force: false)
        }
    }

    init(runtime: TerminiRuntime) {
        self.runtime = runtime
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        updateBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // follow the window's occlusion state so a surface
        // behind other windows / on another Space / minimized stops drawing.
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        guard let window else {
            stopRenderLoop()
            return
        }
        windowIsVisible = window.occlusionState.contains(.visible)
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let visible = self.window?.occlusionState.contains(.visible) ?? false
            guard visible != self.windowIsVisible else { return }
            self.windowIsVisible = visible
            self.renderGateChanged()
        }
        installKeyMonitor()
        if surface != nil {
            // Re-attached to a window (e.g. tab switch) with the surface already
            // live — scheduleSurfaceCreation() no-ops, so re-request focus here.
            renderGateChanged()
            bringToFrontAndFocus()
        } else {
            scheduleSurfaceCreation()
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleSurfaceCreation()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard terminalAppearance.theme == nil else { return }
        applyTerminalAppearanceIfNeeded(force: true)
    }

    deinit {
        stopRenderLoop()
        if let surface {
            ghostty_surface_free(surface)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    // MARK: Focus

    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        setSurfaceFocus(true)
        requestActiveRenderBurst(duration: 0.75)
        logInput("became first responder: \(ok)")
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        setSurfaceFocus(false)
        stopRenderLoop()
        logInput("resigned first responder: \(ok)")
        return ok
    }

    // MARK: Layout

    public override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    public override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateSurfaceSize()
    }

    public override func updateLayer() {
        super.updateLayer()
        updateSurfaceSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceSize()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func updateSurfaceSize() {
        guard let surface else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        ghostty_surface_set_content_scale(surface, scale, scale)
        let width = UInt32(bounds.width * scale)
        let height = UInt32(bounds.height * scale)
        ghostty_surface_set_size(surface, width, height)
        ghostty_surface_refresh(surface)
        // sizing must always reach the surface + PTY (so
        // tmux keeps the right dimensions), but only visible surfaces draw.
        if canRender {
            ghostty_surface_draw(surface)
            requestActiveRenderBurst(duration: 0.35)
        } else {
            needsDrawOnReveal = true
        }
        // MARK: throttle the PTY winsize push.
        scheduleWinsizeReport()
    }

    /// Coalesce PTY winsize pushes (each is a `TIOCSWINSZ` → `SIGWINCH` →
    /// full-screen redraw in the child, e.g. tmux). A live window drag emits
    /// ~60 layout passes/sec; collapsing them to ~12 Hz removes the redraw
    /// storm while the *visual* surface still tracks the window every frame
    /// (`updateSurfaceSize` already set the Ghostty grid above). The final,
    /// authoritative size is pushed in `viewDidEndLiveResize`.
    private func scheduleWinsizeReport() {
        guard pendingWinsizeReport == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWinsizeReport = nil
            self?.reportSizeIfNeeded()
        }
        pendingWinsizeReport = work
        DispatchQueue.main.asyncAfter(deadline: .now() + liveResizeWinsizeInterval, execute: work)
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // Drop any throttled push and send one authoritative final size so the
        // child ends exactly matching the settled window.
        pendingWinsizeReport?.cancel()
        pendingWinsizeReport = nil
        updateSurfaceSize()
        reportSizeIfNeeded()
    }

    // MARK: Rendering

    private enum RenderTimerMode {
        case active
        case focusedIdle
    }

    /// flip the render gate — tell libghostty (its renderer
    /// pauses occluded surfaces internally), stop/restart our own draw timers,
    /// and run the catch-up draw for output that arrived while hidden.
    private func renderGateChanged() {
        if let surface {
            ghostty_surface_set_occlusion(surface, canRender)
        }
        guard canRender else {
            stopRenderLoop()
            return
        }
        if needsDrawOnReveal, let surface {
            needsDrawOnReveal = false
            ghostty_surface_refresh(surface)
            ghostty_surface_draw(surface)
        }
        startFocusedIdleRenderLoopIfNeeded()
    }

    private func requestActiveRenderBurst(duration: TimeInterval = 0.35) {
        guard canRender else { return }   // no bursts while hidden
        renderBurstDeadline = max(renderBurstDeadline, Date().addingTimeInterval(duration))
        startRenderLoop(mode: .active, interval: activeRenderInterval)
    }

    private func startFocusedIdleRenderLoopIfNeeded() {
        guard window?.firstResponder === self else {
            stopRenderLoop()
            return
        }
        startRenderLoop(mode: .focusedIdle, interval: idleFocusedRenderInterval)
    }

    private func startRenderLoop(mode: RenderTimerMode, interval: TimeInterval) {
        guard canRender else { return }   // hidden surfaces run no timers
        if renderTimer != nil, renderTimerMode == mode {
            return
        }

        renderTimer?.invalidate()
        renderTimerMode = mode
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.drawScheduledFrame()
        }
        // tolerance lets the OS coalesce these wakeups.
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func stopRenderLoop() {
        renderTimer?.invalidate()
        renderTimer = nil
        renderTimerMode = nil
    }

    private func drawScheduledFrame() {
        guard let surface else {
            stopRenderLoop()
            return
        }
        // the gate closed since this timer started.
        guard canRender else {
            stopRenderLoop()
            needsDrawOnReveal = true
            return
        }

        switch renderTimerMode {
        case .active:
            ghostty_surface_draw(surface)
            if Date() >= renderBurstDeadline {
                startFocusedIdleRenderLoopIfNeeded()
            }
        case .focusedIdle:
            guard window?.firstResponder === self else {
                stopRenderLoop()
                return
            }
            ghostty_surface_draw(surface)
        case nil:
            stopRenderLoop()
        }
    }

    // MARK: Surface init

    /// Defer surface creation off the synchronous view-lifecycle/layout pass.
    ///
    /// Creating the ghostty surface inline inside `viewDidMoveTo*` blocks the
    /// main thread on the renderer when the view has no window/drawable yet,
    /// which stalls the hosting window's first layout so it never appears.
    /// Schedule it on the next runloop tick, once we're actually in a window.
    private func scheduleSurfaceCreation() {
        guard surface == nil, !surfaceCreationScheduled else { return }
        surfaceCreationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.surfaceCreationScheduled = false
            guard self.surface == nil, self.window != nil else { return }
            self.createSurfaceIfNeeded()
            self.bringToFrontAndFocus()
        }
    }

    private func createSurfaceIfNeeded() {
        guard surface == nil, let app = runtime.app else { return }

        var cfg = ghostty_surface_config_new()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        cfg.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        cfg.font_size = Float(terminalAppearance.fontSize ?? 0)
        cfg.wait_after_command = false

        guard let created = ghostty_surface_new(app, &cfg) else { return }
        surface = created
        // seed the render gate (a warm surface can be
        // created while another one is selected, or the window occluded).
        ghostty_surface_set_occlusion(created, canRender)
        setSurfaceFocus(true)
        updateSurfaceSize()
        ghostty_surface_refresh(created)
        ghostty_surface_draw(created)
        reportSizeIfNeeded()
        scheduleDeferredSurfaceSync()
        requestActiveRenderBurst(duration: 0.75)
        scheduleInitialAppearance()
    }

    /// Mark the surface IO-ready and apply the initial appearance on a later
    /// main-actor turn.
    ///
    /// Output handed to `ghostty_surface_process_output` before the ghostty app
    /// has ticked the freshly-created surface blocks the main thread on the
    /// surface's IO futex — and the `ghostty_app_tick` that would drain it also
    /// runs on the main thread, so it deadlocks. Until then `processRemoteOutput`
    /// buffers (`surfaceIOReady == false`). Here we hop to the next runloop turn,
    /// tick the app so the surface comes up, flip the gate, apply the theme, and
    /// flush anything that arrived in the meantime.
    private func scheduleInitialAppearance() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.surface != nil else { return }
            self.runtime.tick()
            self.surfaceIOReady = true
            self.applyTerminalAppearanceIfNeeded(force: true)
            self.flushPendingOutput()
        }
    }

    private func flushPendingOutput() {
        guard surfaceIOReady, !pendingOutput.isEmpty else { return }
        let buffered = pendingOutput
        pendingOutput = Data()
        processRemoteOutput(buffered)
    }

    private func setSurfaceFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    func handleTransportWrite(_ data: Data) {
        controller?.forwardTransportWrite(data)
    }

    func bind(controller: TerminiTerminalController?) {
        self.controller = controller
        controller?.bind(
            processRemoteOutput: { [weak self] data in
                self?.processRemoteOutput(data)
            },
            focus: { [weak self] in
                self?.bringToFrontAndFocus()
            },
            blur: { [weak self] in
                self?.window?.makeFirstResponder(nil)
            },
            currentSize: { [weak self] in
                self?.currentTerminalSize()
            },
            visibleText: { [weak self] in
                self?.visibleTerminalText()
            },
            diagnostics: {
                nil
            }
        )
        reportSizeIfNeeded()
        scheduleDeferredSurfaceSync()
    }

    private func scheduleDeferredSurfaceSync() {
        DispatchQueue.main.async { [weak self] in
            self?.updateSurfaceSize()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.updateSurfaceSize()
        }
    }

    private func processRemoteOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        // Buffer until the surface exists and has been ticked — feeding an
        // un-ticked surface blocks the main thread (see scheduleInitialAppearance).
        guard surfaceIOReady, let surface else {
            pendingOutput.append(data)
            return
        }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.bindMemory(to: CChar.self).baseAddress else { return }
            ghostty_surface_process_output(surface, ptr, UInt(data.count))
        }
        // hidden surfaces absorb output without drawing (a
        // busy background session must not render invisibly); the reveal path
        // does one catch-up draw. Visible surfaces draw immediately for snappy
        // echo, but immediate draws are capped at ~60 fps — under an output
        // flood the burst timer coalesces frames instead of drawing per chunk.
        guard canRender else {
            needsDrawOnReveal = true
            return
        }
        ghostty_surface_refresh(surface)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastOutputDraw >= minOutputDrawInterval {
            lastOutputDraw = now
            ghostty_surface_draw(surface)
        }
        requestActiveRenderBurst(duration: 0.35)
    }

    private func applyTerminalAppearanceIfNeeded(force: Bool) {
        guard let surface else { return }
        var canCommitAppearanceState = true

        if force || lastAppliedAppearance.theme != terminalAppearance.theme {
            if let theme = terminalAppearance.theme {
                ghostty_surface_set_color_scheme(surface, theme.ghosttyColorScheme)
                processRemoteOutput(Data(theme.applyEscapeSequence.utf8))
            } else if lastAppliedAppearance.theme != nil {
                ghostty_surface_set_color_scheme(surface, ambientGhosttyColorScheme)
                processRemoteOutput(Data(TerminiTerminalTheme.resetEscapeSequence.utf8))
            } else if force {
                ghostty_surface_set_color_scheme(surface, ambientGhosttyColorScheme)
            }
        }

        let fontSizeChanged = lastAppliedAppearance.fontSize != terminalAppearance.fontSize
        let fontFamilyChanged = lastAppliedAppearance.fontFamily != terminalAppearance.fontFamily
        let shouldApplyFontConfig = fontSizeChanged
            || fontFamilyChanged
            || (force && terminalAppearance.hasRuntimeFontOverride)

        if shouldApplyFontConfig {
            guard let config = runtime.makeSurfaceConfig(for: terminalAppearance) else {
                canCommitAppearanceState = false
                return
            }
            defer { ghostty_config_free(config) }

            ghostty_surface_update_config(surface, config)

            if !force, fontSizeChanged {
                scheduleFontSizeBindingUpdate()
            }

            ghostty_surface_refresh(surface)
            ghostty_surface_draw(surface)
            requestActiveRenderBurst(duration: 0.35)
            reportSizeIfNeeded()
        }

        if canCommitAppearanceState {
            lastAppliedAppearance = terminalAppearance
        }
    }

    private func updateBackgroundColor() {
        let color = terminalAppearance.theme?.background ?? .init(hex: 0x000000)
        layer?.backgroundColor = NSColor(
            srgbRed: CGFloat(color.red) / 255.0,
            green: CGFloat(color.green) / 255.0,
            blue: CGFloat(color.blue) / 255.0,
            alpha: 1.0
        ).cgColor
    }

    private var ambientGhosttyColorScheme: ghostty_color_scheme_e {
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua?:
            GHOSTTY_COLOR_SCHEME_DARK
        default:
            GHOSTTY_COLOR_SCHEME_LIGHT
        }
    }

    private func applyBindingAction(_ action: String) {
        guard let surface else { return }
        let success = ghostty_surface_binding_action(
            surface,
            action,
            UInt(action.lengthOfBytes(using: .utf8))
        )
        logInput("\(action) \(success ? "succeeded" : "failed")")
    }

    private func scheduleFontSizeBindingUpdate() {
        let action: String
        if let fontSize = terminalAppearance.fontSize {
            action = "set_font_size:\(String(format: "%.2f", min(max(fontSize, 1), 255)))"
        } else {
            action = "reset_font_size"
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyBindingAction(action)
            guard self.surface != nil else { return }
            ghostty_surface_refresh(self.surface)
            ghostty_surface_draw(self.surface)
            self.requestActiveRenderBurst(duration: 0.35)
            self.reportSizeIfNeeded()
        }
    }

    private func currentTerminalSize() -> TerminiTerminalSize? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        return TerminiTerminalSize(
            columns: Int(size.columns),
            rows: Int(size.rows),
            cellWidthPixels: Int(size.cell_width_px),
            cellHeightPixels: Int(size.cell_height_px)
        )
    }

    private func reportSizeIfNeeded() {
        guard let size = currentTerminalSize() else { return }
        guard size != lastReportedSize else { return }
        lastReportedSize = size
        controller?.reportSizeChanged(size)
    }

    private func visibleTerminalText() -> String? {
        guard let surface, let size = currentTerminalSize() else { return nil }
        guard size.columns > 0, size.rows > 0 else { return nil }

        var text = ghostty_text_s(
            tl_px_x: 0,
            tl_px_y: 0,
            offset_start: 0,
            offset_len: 0,
            text: nil,
            text_len: 0
        )

        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_EXACT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_EXACT,
                x: UInt32(max(size.columns - 1, 0)),
                y: UInt32(max(size.rows - 1, 0))
            ),
            rectangle: false
        )

        guard ghostty_surface_read_text(surface, selection, &text),
              let base = text.text else {
            return nil
        }

        defer { ghostty_surface_free_text(surface, &text) }
        let data = Data(bytes: base, count: Int(text.text_len))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Input

    public override func keyDown(with event: NSEvent) {
        sendKeyEvent(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
    }

    public override func keyUp(with event: NSEvent) {
        sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard window?.firstResponder === self else { return false }
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return false
        }

        return pasteFromClipboard()
    }

    private func modsFromFlags(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func consumedMods(from event: NSEvent, surface: ghostty_surface_t) -> ghostty_input_mods_e {
        // Ask Ghostty to translate modifiers (for option-as-alt, etc) and drop command/control
        // so the engine knows which modifiers contributed to text generation.
        let translated = ghostty_surface_key_translation_mods(surface, modsFromFlags(event.modifierFlags))
        var raw = translated.rawValue
        raw &= ~GHOSTTY_MODS_CTRL.rawValue
        raw &= ~GHOSTTY_MODS_SUPER.rawValue
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        guard event.type == .keyDown || event.type == .keyUp,
              let chars = event.characters(byApplyingModifiers: []),
              let scalar = chars.unicodeScalars.first
        else {
            return 0
        }
        return scalar.value
    }

    private func translatedText(from event: NSEvent) -> String? {
        guard let chars = event.characters else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            // Let Ghostty handle control characters itself.
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            // Ignore private-use range for function keys.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return chars
    }

    private func sendKeyEvent(_ event: NSEvent, action: ghostty_input_action_e) {
        guard let surface else { return }

        var keyEvent = ghostty_input_key_s(
            action: action,
            mods: modsFromFlags(event.modifierFlags),
            consumed_mods: consumedMods(from: event, surface: surface),
            keycode: UInt32(event.keyCode),
            text: nil,
            unshifted_codepoint: unshiftedCodepoint(from: event),
            composing: false
        )

        if let text = translatedText(from: event) {
            let utf8 = text.utf8CString
            utf8.withUnsafeBufferPointer { buffer in
                keyEvent.text = buffer.baseAddress
                ghostty_surface_key(surface, keyEvent)
            }
        } else {
            ghostty_surface_key(surface, keyEvent)
        }
        requestActiveRenderBurst(duration: 0.35)
        logInput("key \(action == GHOSTTY_ACTION_RELEASE ? "up" : "down") keyCode=\(event.keyCode) mods=0x\(String(modsFromFlags(event.modifierFlags).rawValue, radix: 16)) text=\(translatedText(from: event) ?? "<nil>")")
    }

    // MARK: Mouse

    public override func mouseDown(with event: NSEvent) {
        bringToFrontAndFocus()
        setSurfaceFocus(true)
        logInput("mouseDown button=\(event.buttonNumber) loc=\(event.locationInWindow)")
        sendMouse(event, state: GHOSTTY_MOUSE_PRESS)
    }

    public override func mouseUp(with event: NSEvent) {
        logInput("mouseUp button=\(event.buttonNumber) loc=\(event.locationInWindow)")
        sendMouse(event, state: GHOSTTY_MOUSE_RELEASE)
    }

    public override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    public override func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        logInput("otherMouseDown button=\(event.buttonNumber) loc=\(event.locationInWindow)")
        mouseDown(with: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        logInput("otherMouseUp button=\(event.buttonNumber) loc=\(event.locationInWindow)")
        mouseUp(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        sendMouseMove(event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        sendMouseMove(event)
    }

    public override func otherMouseDragged(with event: NSEvent) {
        sendMouseMove(event)
    }

    public override func mouseMoved(with event: NSEvent) {
        sendMouseMove(event)
    }

    // The last argument of ghostty_surface_mouse_scroll is NOT keyboard mods:
    // bit 0 is the precision flag and bits 1–3 the momentum phase (ghostty
    // src/input/mouse.zig). Passing the keyboard-modifier bitmask made ghostty
    // treat trackpad *pixel* deltas as discrete wheel ticks, multiplying each
    // by the cell height — one line scrolled per pixel of finger travel (and
    // holding shift flipped the precision bit). Mirror ghostty's own AppKit
    // surface view instead: precise deltas are pixels (with ghostty's 2x feel
    // multiplier), discrete wheel ticks pass through unscaled, and the
    // momentum phase is forwarded so inertial scrolling behaves.
    public override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }
        let momentum: ghostty_input_mouse_momentum_e
        switch event.momentumPhase {
        case .began: momentum = GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary: momentum = GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed: momentum = GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended: momentum = GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled: momentum = GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin: momentum = GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default: momentum = GHOSTTY_MOUSE_MOMENTUM_NONE
        }
        let scrollMods = ghostty_input_scroll_mods_t(
            (precision ? 1 : 0) | (Int32(momentum.rawValue) << 1)
        )
        ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
        requestActiveRenderBurst(duration: 0.35)
        logInput("scroll dx=\(x) dy=\(y) precision=\(precision) momentum=\(momentum.rawValue)")
    }

    private func sendMouse(_ event: NSEvent, state: ghostty_input_mouse_state_e) {
        guard let surface else { return }
        let mods = modsFromFlags(event.modifierFlags)
        let button = mouseButton(from: event)
        ghostty_surface_mouse_button(surface, state, button, mods)
        requestActiveRenderBurst(duration: 0.35)
        sendMouseMove(event)
    }

    private func sendMouseMove(_ event: NSEvent) {
        guard let surface else { return }
        let location = convert(event.locationInWindow, from: nil)
        let mods = modsFromFlags(event.modifierFlags)
        let flippedY = bounds.height - location.y
        ghostty_surface_mouse_pos(surface, location.x, flippedY, mods)
        requestActiveRenderBurst(duration: 0.2)
        logMouseInput("mouseMove x=\(location.x) y=\(location.y) mods=0x\(String(mods.rawValue, radix: 16))")
    }

    private func mouseButton(from event: NSEvent) -> ghostty_input_mouse_button_e {
        switch event.buttonNumber {
        case 0:
            return GHOSTTY_MOUSE_LEFT
        case 1:
            return GHOSTTY_MOUSE_RIGHT
        case 2:
            return GHOSTTY_MOUSE_MIDDLE
        default:
            return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    private func bringToFrontAndFocus() {
        // Make sure the app and window are active before requesting first responder.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.acceptsMouseMovedEvents = true
        // Defer to next runloop to ensure the window is ready.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
            self.logInput("requested first responder (keyWindow=\(self.window?.isKeyWindow == true), appActive=\(NSApp.isActive))")
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            guard event.window == self.window, self.window?.firstResponder === self else {
                return event
            }
            self.logInput("monitor saw \(event.type == .keyDown ? "down" : "up") keyCode=\(event.keyCode) mods=0x\(String(self.modsFromFlags(event.modifierFlags).rawValue, radix: 16)) isKeyWindow=\(self.window?.isKeyWindow == true) firstResponder=\(String(describing: self.window?.firstResponder))")
            if event.modifierFlags.contains(.command) {
                return event
            }
            switch event.type {
            case .keyDown:
                self.sendKeyEvent(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
                return nil
            case .keyUp:
                self.sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
                return nil
            default:
                return event
            }
        }
    }

    // MARK: Debug

    private func logInput(_ message: String) {
        guard debugInputLogging else { return }
        NSLog("[TerminiSurface] \(message)")
    }

    private func logMouseInput(_ message: String) {
        guard debugInputLogging else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMouseLog >= mouseLogInterval {
            lastMouseLog = now
            NSLog("[TerminiSurface] \(message)")
        }
    }

    // MARK: Clipboard

    @IBAction public func paste(_ sender: Any?) {
        _ = pasteFromClipboard()
    }

    @IBAction public func pasteAsPlainText(_ sender: Any?) {
        _ = pasteFromClipboard()
    }

    func readClipboard(
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let pasteboard = pasteboard(for: location),
              let string = pasteboardString(from: pasteboard) else {
            return false
        }

        completeClipboardRequest(string, state: state)
        return true
    }

    func completeClipboardRequest(
        _ string: String,
        state: UnsafeMutableRawPointer?,
        confirmed: Bool = false
    ) {
        guard let surface else { return }
        string.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
        }
    }

    private func pasteFromClipboard() -> Bool {
        guard let surface else { return false }
        let action = "paste_from_clipboard"
        let success = ghostty_surface_binding_action(
            surface,
            action,
            UInt(action.lengthOfBytes(using: .utf8))
        )
        requestActiveRenderBurst(duration: 0.35)
        logInput("paste_from_clipboard \(success ? "succeeded" : "failed")")
        return success
    }

    private func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        default:
            return nil
        }
    }

    private func pasteboardString(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           !urls.isEmpty {
            return urls.map(\.path).joined(separator: " ")
        }

        return pasteboard.string(forType: .string)
    }
}

private extension TerminiTerminalTheme {
    var ghosttyColorScheme: ghostty_color_scheme_e {
        switch colorScheme {
        case .dark:
            GHOSTTY_COLOR_SCHEME_DARK
        case .light:
            GHOSTTY_COLOR_SCHEME_LIGHT
        }
    }
}

#endif
