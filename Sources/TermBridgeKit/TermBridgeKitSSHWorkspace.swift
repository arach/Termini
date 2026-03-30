import Foundation
import Observation

@MainActor
@Observable
public final class TermBridgeKitSSHWorkspace {
    public let controller: TermBridgeKitTerminalController
    public let guide: TermBridgeKitConnectionGuide

    public var connection: TermBridgeKitConnectionConfig
    public private(set) var status: TermBridgeKitSSHSession.Status = .disconnected
    public private(set) var terminalSize: TermBridgeKitTerminalSize?
    public private(set) var diagnostics: TermBridgeKitSurfaceDiagnostics?
    public private(set) var statusMessage: String
    public private(set) var lastErrorMessage: String?
    public private(set) var didLoadEnvironmentConfiguration = false

    private var session: TermBridgeKitSSHSession?

    public init(
        connection: TermBridgeKitConnectionConfig = .init(),
        guide: TermBridgeKitConnectionGuide = .sshStarter,
        controller: TermBridgeKitTerminalController
    ) {
        self.connection = connection
        self.guide = guide
        self.controller = controller
        self.statusMessage = "Configure a host to start."

        controller.onSizeChange = { [weak self] size in
            self?.terminalSize = size
        }

        controller.onDiagnosticsChange = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
        }
    }

    public convenience init(
        connection: TermBridgeKitConnectionConfig = .init(),
        guide: TermBridgeKitConnectionGuide = .sshStarter
    ) {
        self.init(
            connection: connection,
            guide: guide,
            controller: TermBridgeKitTerminalController()
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
        guard let configuration = TermBridgeKitConnectionConfig.demoEnvironment(environment) else {
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
        await ensureSession().connect(configuration: configuration)
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

    private func ensureSession() -> TermBridgeKitSSHSession {
        if let session {
            return session
        }

        let session = TermBridgeKitSSHSession(controller: controller)
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
