import SwiftUI
import TermBridgeKit

struct ContentView: View {
    @State private var controller = TermBridgeKitTerminalController()
    @State private var sshSession: TermBridgeKitSSHSession?
    @State private var didStartSSHConnection = false
    @State private var terminalSize: TermBridgeKitTerminalSize?
    @State private var connectionStatus = "Waiting for demo SSH configuration…"

    var body: some View {
        ZStack(alignment: .topLeading) {
            TermBridgeKitTerminalView(controller: controller)
                .ignoresSafeArea()

            if shouldShowStatusBanner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH Claude Demo")
                        .font(.caption.weight(.semibold))
                    Text(connectionStatus)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if let terminalSize {
                        Text("\(terminalSize.columns)x\(terminalSize.rows)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding()
            }
        }
        .background(.black)
        .task {
            let session = ensureSSHSession()

            controller.onSizeChange = { size in
                terminalSize = size
                session.updateTerminalSize(size)
            }

            guard !didStartSSHConnection else { return }
            didStartSSHConnection = true
            guard let configuration = DemoSSHConfig.configuration else {
                connectionStatus = DemoSSHConfig.instructions
                return
            }
            await session.connect(configuration: configuration)
        }
    }

    private var shouldShowStatusBanner: Bool {
        switch sshSession?.status {
        case .connected:
            return false
        case .none, .disconnected, .connecting, .failed:
            return true
        }
    }

    private func ensureSSHSession() -> TermBridgeKitSSHSession {
        if let sshSession {
            return sshSession
        }

        let session = TermBridgeKitSSHSession(controller: controller)
        session.onStatusChange = { status in
            switch status {
            case .disconnected:
                connectionStatus = "Disconnected"
            case .connecting:
                connectionStatus = "Connecting to \(DemoSSHConfig.hostLabel)…"
            case .connected:
                connectionStatus = "Connected to \(DemoSSHConfig.hostLabel)"
            case .failed(let message):
                connectionStatus = "SSH failed: \(message)"
            }
        }
        sshSession = session
        return session
    }
}

private enum DemoSSHConfig {
    static var configuration: TermBridgeKitSSHConfiguration? {
        let environment = ProcessInfo.processInfo.environment

        guard let host = nonEmpty(environment["TERMBRIDGEKIT_SSH_HOST"]),
              let username = nonEmpty(environment["TERMBRIDGEKIT_SSH_USER"])
        else {
            return nil
        }

        let password = nonEmpty(environment["TERMBRIDGEKIT_SSH_PASSWORD"]) ?? ""
        let privateKey = nonEmpty(environment["TERMBRIDGEKIT_SSH_PRIVATE_KEY"])?
            .replacingOccurrences(of: "\\n", with: "\n")

        guard !password.isEmpty || privateKey != nil else {
            return nil
        }

        let port = Int(environment["TERMBRIDGEKIT_SSH_PORT"] ?? "") ?? 22
        let command = nonEmpty(environment["TERMBRIDGEKIT_SSH_COMMAND"])

        return TermBridgeKitSSHConfiguration(
            host: host,
            port: port,
            username: username,
            password: password,
            privateKeyPEM: privateKey,
            startupCommand: command
        )
    }

    static var hostLabel: String {
        nonEmpty(ProcessInfo.processInfo.environment["TERMBRIDGEKIT_SSH_HOST"]) ?? "SSH host"
    }

    static var instructions: String {
        "Set TERMBRIDGEKIT_SSH_HOST, _USER, and _PRIVATE_KEY."
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
