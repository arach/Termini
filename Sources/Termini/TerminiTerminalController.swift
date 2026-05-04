import Foundation

public struct TerminiTerminalSize: Equatable, Sendable {
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

public struct TerminiSurfaceDiagnostics: Equatable, Sendable {
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public var summary: String {
        lines.joined(separator: "\n")
    }
}

@MainActor
public final class TerminiTerminalController {
    private var processRemoteOutputImpl: ((Data) -> Void)?
    private var focusImpl: (() -> Void)?
    private var blurImpl: (() -> Void)?
    private var currentSizeImpl: (() -> TerminiTerminalSize?)?
    private var visibleTextImpl: (() -> String?)?
    private var diagnosticsImpl: (() -> TerminiSurfaceDiagnostics?)?
    private var pendingOutputChunks: [Data] = []
    private var latestSize: TerminiTerminalSize?
    private var latestDiagnostics: TerminiSurfaceDiagnostics?
    private var isSizeNotificationScheduled = false
    private var isDiagnosticsNotificationScheduled = false

    public var onInputText: ((String) -> Void)?
    public var onDeleteBackward: (() -> Void)?
    public var onTransportWrite: ((Data) -> Void)?

    public var onSizeChange: ((TerminiTerminalSize) -> Void)? {
        didSet {
            scheduleSizeNotificationIfNeeded()
        }
    }

    public var onDiagnosticsChange: ((TerminiSurfaceDiagnostics) -> Void)? {
        didSet {
            scheduleDiagnosticsNotificationIfNeeded()
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

    public func currentSize() -> TerminiTerminalSize? {
        currentSizeImpl?()
    }

    public func visibleText() -> String? {
        visibleTextImpl?()
    }

    public func diagnostics() -> TerminiSurfaceDiagnostics? {
        diagnosticsImpl?()
    }

    func bind(
        processRemoteOutput: @escaping (Data) -> Void,
        focus: @escaping () -> Void,
        blur: @escaping () -> Void,
        currentSize: @escaping () -> TerminiTerminalSize?,
        visibleText: @escaping () -> String?,
        diagnostics: @escaping () -> TerminiSurfaceDiagnostics?
    ) {
        processRemoteOutputImpl = processRemoteOutput
        focusImpl = focus
        blurImpl = blur
        currentSizeImpl = currentSize
        visibleTextImpl = visibleText
        diagnosticsImpl = diagnostics

        if let size = currentSize() {
            latestSize = size
            scheduleSizeNotificationIfNeeded()
        }

        if let diagnostics = diagnostics() {
            latestDiagnostics = diagnostics
            scheduleDiagnosticsNotificationIfNeeded()
        }

        guard !pendingOutputChunks.isEmpty else { return }
        let chunks = pendingOutputChunks
        pendingOutputChunks.removeAll(keepingCapacity: true)
        for chunk in chunks {
            processRemoteOutput(chunk)
        }
    }

    func reportSizeChanged(_ size: TerminiTerminalSize) {
        latestSize = size
        scheduleSizeNotificationIfNeeded()
    }

    func reportDiagnosticsChanged(_ diagnostics: TerminiSurfaceDiagnostics) {
        latestDiagnostics = diagnostics
        scheduleDiagnosticsNotificationIfNeeded()
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

    private func scheduleSizeNotificationIfNeeded() {
        guard latestSize != nil, !isSizeNotificationScheduled else { return }
        isSizeNotificationScheduled = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSizeNotificationScheduled = false
            guard let latestSize = self.latestSize else { return }
            self.onSizeChange?(latestSize)
        }
    }

    private func scheduleDiagnosticsNotificationIfNeeded() {
        guard latestDiagnostics != nil, !isDiagnosticsNotificationScheduled else { return }
        isDiagnosticsNotificationScheduled = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isDiagnosticsNotificationScheduled = false
            guard let latestDiagnostics = self.latestDiagnostics else { return }
            self.onDiagnosticsChange?(latestDiagnostics)
        }
    }
}
