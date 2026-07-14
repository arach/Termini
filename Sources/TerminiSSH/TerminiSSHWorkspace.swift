import Termini
import Foundation
import Observation

@MainActor
@Observable
public final class TerminiSSHWorkspace {
    public let controller: TerminiTerminalController
    public let guide: TerminiConnectionGuide

    public var connection: TerminiConnectionConfig
    public private(set) var status: TerminiSSHSession.Status = .disconnected
    public private(set) var terminalSize: TerminiTerminalSize?
    public private(set) var diagnostics: TerminiSurfaceDiagnostics?
    public private(set) var statusMessage: String
    public private(set) var lastErrorMessage: String?
    public private(set) var didLoadEnvironmentConfiguration = false

    private var session: TerminiSSHSession?

    public init(
        connection: TerminiConnectionConfig = .init(),
        guide: TerminiConnectionGuide = .sshStarter,
        controller: TerminiTerminalController
    ) {
        self.connection = connection
        self.guide = guide
        self.controller = controller
        self.statusMessage = "Configure a host to start."

        controller.onSizeChange = { [weak self] size in
            self?.terminalSize = size
            self?.session?.updateTerminalSize(size)
        }

        controller.onDiagnosticsChange = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
        }
    }

    public convenience init(
        connection: TerminiConnectionConfig = .init(),
        guide: TerminiConnectionGuide = .sshStarter
    ) {
        self.init(
            connection: connection,
            guide: guide,
            controller: TerminiTerminalController()
        )
    }

    public var isConnected: Bool {
        if case .connected = status {
            return true
        }
        return false
    }

    public var isConnecting: Bool {
        if case .connecting = status {
            return true
        }
        return false
    }

    public var canConnect: Bool {
        !isConnecting && connection.isReadyToConnect
    }

    @discardableResult
    public func loadEnvironmentConfigurationIfAvailable(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let configuration = TerminiConnectionConfig.demoEnvironment(environment) else {
            return false
        }

        connection = configuration
        didLoadEnvironmentConfiguration = true
        statusMessage = "Loaded demo configuration for \(configuration.endpointLabel)."
        return true
    }

    public func connect() async {
        guard let configuration = connection.resolvedSSHConfiguration() else {
            let message = connection.validationError ?? "Connection details are incomplete."
            status = .failed(message)
            lastErrorMessage = message
            statusMessage = message
            return
        }

        lastErrorMessage = nil
        statusMessage = "Connecting to \(connection.endpointLabel)…"
        let session = ensureSession()
        if let terminalSize {
            session.updateTerminalSize(terminalSize)
        }
        await session.connect(configuration: configuration)
    }

    public func disconnect() async {
        guard let session else {
            status = .disconnected
            statusMessage = "Disconnected."
            return
        }

        await session.disconnect()
    }

    public func toggleConnection() async {
        if isConnected || isConnecting {
            await disconnect()
        } else {
            await connect()
        }
    }

    private func ensureSession() -> TerminiSSHSession {
        if let session {
            return session
        }

        let session = TerminiSSHSession(controller: controller)
        session.onStatusChange = { [weak self, weak session] status in
            guard let self else { return }
            self.status = status

            let endpoint = session?.endpointLabel ?? self.connection.endpointLabel
            switch status {
            case .disconnected:
                self.lastErrorMessage = nil
                self.statusMessage = "Disconnected from \(endpoint)."
            case .connecting:
                self.lastErrorMessage = nil
                self.statusMessage = "Connecting to \(endpoint)…"
            case .connected:
                self.lastErrorMessage = nil
                self.statusMessage = "Connected to \(endpoint)."
            case .failed(let message):
                self.lastErrorMessage = message
                self.statusMessage = "Connection failed: \(message)"
            }
        }
        self.session = session
        return session
    }
}
