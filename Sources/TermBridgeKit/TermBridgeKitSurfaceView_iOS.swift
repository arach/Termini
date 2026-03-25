#if canImport(UIKit)

import SwiftUI
import UIKit
import GhosttyKit

/// SwiftUI wrapper that embeds the live Ghostty surface on iOS.
public struct TermBridgeKitSurfaceView: UIViewRepresentable {
    private let controller: TermBridgeKitTerminalController?

    public init(controller: TermBridgeKitTerminalController? = nil) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> SurfaceContainerView {
        let view = SurfaceContainerView(runtime: .shared)
        view.bind(controller: controller)
        return view
    }

    public func updateUIView(_ uiView: SurfaceContainerView, context: Context) {
        uiView.bind(controller: controller)
    }
}

/// UIView subclass that hosts the Ghostty surface and forwards basic iOS input.
public final class SurfaceContainerView: UIView, UIKeyInput, UITextInputTraits {
    private let runtime: TermBridgeKitRuntime
    private var surface: ghostty_surface_t?
    private var renderLink: CADisplayLink?
    private weak var controller: TermBridgeKitTerminalController?
    private var lastReportedSize: TermBridgeKitTerminalSize?

    public var keyboardType: UIKeyboardType = .asciiCapable
    public var autocorrectionType: UITextAutocorrectionType = .no
    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var enablesReturnKeyAutomatically: Bool = false

    public var hasText: Bool { true }

    public override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    init(runtime: TermBridgeKitRuntime) {
        self.runtime = runtime
        // Ghostty expects a non-zero host view so its internal IOSurface layer can size itself.
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        backgroundColor = .black
        isOpaque = true
        contentScaleFactor = UIScreen.main.scale
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        renderLink?.invalidate()
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        createSurfaceIfNeeded()
        synchronizeGhosttyLayerGeometry()
        updateSurfaceSize()
        startRenderLoopIfNeeded()
        Task { @MainActor in
            _ = self.becomeFirstResponder()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        synchronizeGhosttyLayerGeometry()
        updateSurfaceSize()
    }

    public override var canBecomeFirstResponder: Bool { true }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        setSurfaceFocus(true)
        runtime.keyboardDidChange()
        return ok
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        setSurfaceFocus(false)
        return ok
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        _ = becomeFirstResponder()
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if forward(presses: presses, action: GHOSTTY_ACTION_PRESS) {
            return
        }
        super.pressesBegan(presses, with: event)
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if forward(presses: presses, action: GHOSTTY_ACTION_RELEASE) {
            return
        }
        super.pressesEnded(presses, with: event)
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if forward(presses: presses, action: GHOSTTY_ACTION_RELEASE) {
            return
        }
        super.pressesCancelled(presses, with: event)
    }

    public func insertText(_ text: String) {
        if controller?.forwardInputText(text) == true {
            return
        }
        sendText(text)
    }

    public func deleteBackward() {
        if controller?.forwardDeleteBackward() == true {
            return
        }
        sendText("\u{7F}")
    }

    private func startRenderLoopIfNeeded() {
        guard renderLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(drawFrame))
        link.add(to: .main, forMode: .common)
        renderLink = link
    }

    @objc
    private func drawFrame() {
        guard let surface else { return }
        ghostty_surface_draw(surface)
    }

    func bind(controller: TermBridgeKitTerminalController?) {
        self.controller = controller
        controller?.bind(
            processRemoteOutput: { [weak self] data in
                self?.processRemoteOutput(data)
            },
            focus: { [weak self] in
                _ = self?.becomeFirstResponder()
            },
            blur: { [weak self] in
                _ = self?.resignFirstResponder()
            },
            currentSize: { [weak self] in
                self?.currentTerminalSize()
            },
            visibleText: { [weak self] in
                self?.visibleTerminalText()
            },
            diagnostics: { [weak self] in
                self?.surfaceDiagnostics()
            }
        )
        reportSizeIfNeeded()
        reportDiagnostics()
    }

    private func createSurfaceIfNeeded() {
        guard surface == nil, let app = runtime.app else { return }

        var cfg = ghostty_surface_config_new()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.platform_tag = GHOSTTY_PLATFORM_IOS
        cfg.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(
            uiview: Unmanaged.passUnretained(self).toOpaque()
        ))
        cfg.scale_factor = Double(window?.screen.scale ?? UIScreen.main.scale)
        cfg.font_size = 0
        cfg.wait_after_command = false

        guard let created = ghostty_surface_new(app, &cfg) else { return }
        surface = created
        synchronizeGhosttyLayerGeometry()
        setSurfaceFocus(true)
        updateSurfaceSize()
        ghostty_surface_refresh(created)
        ghostty_surface_draw(created)
        reportSizeIfNeeded()
        reportDiagnostics()
    }

    private func updateSurfaceSize() {
        guard let surface else { return }
        let scale = Double(window?.screen.scale ?? UIScreen.main.scale)
        ghostty_surface_set_content_scale(surface, scale, scale)
        let width = UInt32(bounds.width * scale)
        let height = UInt32(bounds.height * scale)
        ghostty_surface_set_size(surface, width, height)
        ghostty_surface_refresh(surface)
        ghostty_surface_draw(surface)
        reportSizeIfNeeded()
        reportDiagnostics()
    }

    private func setSurfaceFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    private func sendText(_ text: String) {
        guard let surface else { return }
        let len = text.utf8CString.count
        guard len > 0 else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }
    }

    private func processRemoteOutput(_ data: Data) {
        guard let surface, !data.isEmpty else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.bindMemory(to: CChar.self).baseAddress else { return }
            ghostty_surface_process_output(surface, ptr, UInt(data.count))
        }
        ghostty_surface_refresh(surface)
        ghostty_surface_draw(surface)
        reportDiagnostics()
    }

    private func currentTerminalSize() -> TermBridgeKitTerminalSize? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        return TermBridgeKitTerminalSize(
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

    private func synchronizeGhosttyLayerGeometry() {
        let hostBounds = layer.bounds
        let scale = window?.screen.scale ?? UIScreen.main.scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = scale
        for sublayer in layer.sublayers ?? [] {
            sublayer.frame = hostBounds
            sublayer.contentsScale = scale
            sublayer.setNeedsDisplay()
        }
        CATransaction.commit()
    }

    private func reportDiagnostics() {
        guard let diagnostics = surfaceDiagnostics() else { return }
        controller?.reportDiagnosticsChanged(diagnostics)
    }

    private func surfaceDiagnostics() -> TermBridgeKitSurfaceDiagnostics? {
        let hostLayer = layer
        let sublayers = hostLayer.sublayers ?? []

        func describe(_ rect: CGRect) -> String {
            "\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.size.width))x\(Int(rect.size.height))"
        }

        var lines = [
            "view.bounds \(describe(bounds))",
            "host.layer \(String(describing: type(of: hostLayer))) \(describe(hostLayer.bounds)) scale=\(hostLayer.contentsScale)",
            "window=\(window != nil) firstResponder=\(isFirstResponder) sublayers=\(sublayers.count)"
        ]

        for (index, sublayer) in sublayers.prefix(3).enumerated() {
            lines.append(
                "sub[\(index)] \(String(describing: type(of: sublayer))) frame=\(describe(sublayer.frame)) bounds=\(describe(sublayer.bounds)) scale=\(sublayer.contentsScale)"
            )
        }

        if let size = currentTerminalSize() {
            lines.append("grid \(size.columns)x\(size.rows) cell=\(size.cellWidthPixels)x\(size.cellHeightPixels)")
        } else {
            lines.append("grid unavailable")
        }

        return TermBridgeKitSurfaceDiagnostics(lines: lines)
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

    private func forward(presses: Set<UIPress>, action: ghostty_input_action_e) -> Bool {
        guard let surface else { return false }
        var handledAny = false

        for press in presses {
            guard let key = press.key else { continue }
            handledAny = true

            let text = key.characters

            var keyEvent = ghostty_input_key_s(
                action: action,
                mods: mods(from: key.modifierFlags),
                consumed_mods: GHOSTTY_MODS_NONE,
                keycode: UInt32(key.keyCode.rawValue),
                text: nil,
                unshifted_codepoint: key.charactersIgnoringModifiers.unicodeScalars.first?.value ?? 0,
                composing: false
            )

            if text.isEmpty {
                ghostty_surface_key(surface, keyEvent)
            } else {
                text.utf8CString.withUnsafeBufferPointer { buffer in
                    keyEvent.text = buffer.baseAddress
                    ghostty_surface_key(surface, keyEvent)
                }
            }
        }

        return handledAny
    }

    private func mods(from flags: UIKeyModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.alternate) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.alphaShift) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }
}

#endif
