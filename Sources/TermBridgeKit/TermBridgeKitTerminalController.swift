import Foundation

public struct TermBridgeKitTerminalSize: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellWidthPixels: Int
    public let cellHeightPixels: Int

    public init(
        columns: Int,
        rows: Int,
        cellWidthPixels: Int,
        cellHeightPixels: Int
    ) {
        self.columns = columns
        self.rows = rows
        self.cellWidthPixels = cellWidthPixels
        self.cellHeightPixels = cellHeightPixels
    }
}

public struct TermBridgeKitSurfaceDiagnostics: Equatable, Sendable {
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public var summary: String {
        lines.joined(separator: "\n")
    }
}

@MainActor
public final class TermBridgeKitTerminalController {
    private var processRemoteOutputImpl: ((Data) -> Void)?
    private var focusImpl: (() -> Void)?
    private var blurImpl: (() -> Void)?
    private var currentSizeImpl: (() -> TermBridgeKitTerminalSize?)?
    private var visibleTextImpl: (() -> String?)?
    private var diagnosticsImpl: (() -> TermBridgeKitSurfaceDiagnostics?)?
    private var pendingOutputChunks: [Data] = []
    private var latestSize: TermBridgeKitTerminalSize?
    private var latestDiagnostics: TermBridgeKitSurfaceDiagnostics?

    public var onInputText: ((String) -> Void)?
    public var onDeleteBackward: (() -> Void)?
    public var onTransportWrite: ((Data) -> Void)?

    public var onSizeChange: ((TermBridgeKitTerminalSize) -> Void)? {
        didSet {
            guard let latestSize else { return }
            onSizeChange?(latestSize)
        }
    }

    public var onDiagnosticsChange: ((TermBridgeKitSurfaceDiagnostics) -> Void)? {
        didSet {
            guard let latestDiagnostics else { return }
            onDiagnosticsChange?(latestDiagnostics)
        }
    }

    public init() {}

    public func processRemoteOutput(_ data: Data) {
        guard !data.isEmpty else { return }

        if let processRemoteOutputImpl {
            processRemoteOutputImpl(data)
        } else {
            pendingOutputChunks.append(data)
        }
    }

    public func focus() {
        focusImpl?()
    }

    public func blur() {
        blurImpl?()
    }

    public func currentSize() -> TermBridgeKitTerminalSize? {
        currentSizeImpl?()
    }

    public func visibleText() -> String? {
        visibleTextImpl?()
    }

    public func diagnostics() -> TermBridgeKitSurfaceDiagnostics? {
        diagnosticsImpl?()
    }

    func bind(
        processRemoteOutput: @escaping (Data) -> Void,
        focus: @escaping () -> Void,
        blur: @escaping () -> Void,
        currentSize: @escaping () -> TermBridgeKitTerminalSize?,
        visibleText: @escaping () -> String?,
        diagnostics: @escaping () -> TermBridgeKitSurfaceDiagnostics?
    ) {
        processRemoteOutputImpl = processRemoteOutput
        focusImpl = focus
        blurImpl = blur
        currentSizeImpl = currentSize
        visibleTextImpl = visibleText
        diagnosticsImpl = diagnostics

        if let size = currentSize() {
            latestSize = size
            onSizeChange?(size)
        }

        if let diagnostics = diagnostics() {
            latestDiagnostics = diagnostics
            onDiagnosticsChange?(diagnostics)
        }

        guard !pendingOutputChunks.isEmpty else { return }
        let chunks = pendingOutputChunks
        pendingOutputChunks.removeAll(keepingCapacity: true)
        for chunk in chunks {
            processRemoteOutput(chunk)
        }
    }

    func reportSizeChanged(_ size: TermBridgeKitTerminalSize) {
        latestSize = size
        onSizeChange?(size)
    }

    func reportDiagnosticsChanged(_ diagnostics: TermBridgeKitSurfaceDiagnostics) {
        latestDiagnostics = diagnostics
        onDiagnosticsChange?(diagnostics)
    }

    func forwardInputText(_ text: String) -> Bool {
        guard let onInputText else { return false }
        onInputText(text)
        return true
    }

    func forwardDeleteBackward() -> Bool {
        guard let onDeleteBackward else { return false }
        onDeleteBackward()
        return true
    }

    func forwardTransportWrite(_ data: Data) {
        guard !data.isEmpty else { return }
        onTransportWrite?(data)
    }
}
