#if os(macOS)
import Foundation
import Observation

@MainActor
@Observable
public final class TerminiLocalPTYWorkspace {
    public enum Status: Equatable, Sendable {
        case disconnected
        case running
        case failed(String)
    }

    public let controller: TerminiTerminalController
    public var processSpec: TerminiProcessSpec
    public private(set) var status: Status = .disconnected
    public private(set) var terminalSize: TerminiTerminalSize?
    public private(set) var diagnostics: TerminiSurfaceDiagnostics?
    public private(set) var statusMessage: String
    public private(set) var lastErrorMessage: String?
    public private(set) var lastExitCode: Int32?

    private var process: TerminiLocalPTYProcess?

    public init(
        processSpec: TerminiProcessSpec? = nil,
        controller: TerminiTerminalController
    ) {
        self.processSpec = processSpec ?? Self.defaultShellSpec()
        self.controller = controller
        self.statusMessage = "Ready to start local shell."

        controller.onSizeChange = { [weak self] size in
            guard let self else { return }
            self.terminalSize = size
            self.process?.resize(to: .init(columns: size.columns, rows: size.rows))
        }

        controller.onDiagnosticsChange = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
        }

        controller.onInputText = { [weak self] text in
            self?.send(text.data(using: .utf8) ?? Data())
        }
        controller.onDeleteBackward = { [weak self] in
            self?.send(Data([0x7f]))
        }
        controller.onTransportWrite = { [weak self] data in
            self?.send(data)
        }
    }

    public convenience init(processSpec: TerminiProcessSpec? = nil) {
        self.init(
            processSpec: processSpec,
            controller: TerminiTerminalController()
        )
    }

    public var isRunning: Bool {
        if case .running = status {
            return true
        }
        return false
    }

    public func start() {
        stop()
        lastErrorMessage = nil
        lastExitCode = nil
        statusMessage = "Starting \(processSpec.executableURL.lastPathComponent)…"

        let process = TerminiLocalPTYProcess()
        process.onOutput = { [weak controller] data in
            Task { @MainActor in
                controller?.processRemoteOutput(data)
            }
        }
        process.onExit = { [weak self] exitCode in
            Task { @MainActor [weak self] in
                self?.handleExit(exitCode)
            }
        }

        do {
            try process.start(
                spec: processSpec,
                initialSize: currentPTYSize()
            )
            self.process = process
            status = .running
            statusMessage = "Running \(processSpec.executableURL.lastPathComponent)."
        } catch {
            self.process = nil
            let message = error.localizedDescription
            status = .failed(message)
            lastErrorMessage = message
            statusMessage = "Local shell failed: \(message)"
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
        if !isRunning {
            status = .disconnected
            statusMessage = "Disconnected."
        }
    }

    public func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    public func send(_ data: Data) {
        process?.send(data)
    }

    public func resize(to size: TerminiLocalPTYProcess.Size) {
        process?.resize(to: size)
    }

    private func handleExit(_ exitCode: Int32) {
        process = nil
        lastExitCode = exitCode
        status = .disconnected
        statusMessage = "Local shell exited with code \(exitCode)."
    }

    private func currentPTYSize() -> TerminiLocalPTYProcess.Size {
        if let currentSize = controller.currentSize() ?? terminalSize {
            return .init(columns: currentSize.columns, rows: currentSize.rows)
        }
        return .default
    }

    private static func defaultShellSpec() -> TerminiProcessSpec {
        let environment = ProcessInfo.processInfo.environment
        let shellPath = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let workingDirectory = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return TerminiProcessSpec(
            executableURL: URL(fileURLWithPath: shellPath),
            arguments: ["-l"],
            environment: [:],
            workingDirectoryURL: URL(fileURLWithPath: workingDirectory)
        )
    }
}
#endif
