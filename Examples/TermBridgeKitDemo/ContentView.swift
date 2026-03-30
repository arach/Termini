import SwiftUI
import TermBridgeKit

private enum DemoSidebarDestination: Hashable {
    case connection
    case guide
}

struct ContentView: View {
    @State private var workspace = TermBridgeKitSSHWorkspace(
        connection: .init(startupCommand: "tmux new -A -s termbridgekit")
    )
    @State private var selection: DemoSidebarDestination? = .connection
    @State private var didBootstrap = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: DemoSidebarDestination.connection) {
                    Label("Connection", systemImage: "terminal")
                }

                NavigationLink(value: DemoSidebarDestination.guide) {
                    Label("Guide", systemImage: "book.closed")
                }
            }
            .navigationTitle("Starter")
        } detail: {
            switch selection ?? .connection {
            case .connection:
                DesktopConnectionScreen(workspace: workspace)
            case .guide:
                DesktopGuideScreen(guide: workspace.guide)
            }
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            if workspace.loadEnvironmentConfigurationIfAvailable() {
                await workspace.connect()
            }
        }
    }
}

private struct DesktopConnectionScreen: View {
    let workspace: TermBridgeKitSSHWorkspace

    var body: some View {
        HSplitView {
            DesktopConnectionInspector(workspace: workspace)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            DesktopTerminalPane(workspace: workspace)
        }
        .navigationTitle("SSH Starter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(workspace.isConnected ? "Disconnect" : "Connect") {
                    Task {
                        await workspace.toggleConnection()
                    }
                }
                .disabled(!workspace.isConnected && !workspace.canConnect)
            }
        }
    }
}

private struct DesktopConnectionInspector: View {
    @Bindable var workspace: TermBridgeKitSSHWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connection")
                        .font(.title2.weight(.semibold))
                    Text("This is the app-facing layer above the raw terminal surface. Configure the host here and let the workspace manage the SSH session.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Connection Name", text: $workspace.connection.name)

                    TextField("Host", text: $workspace.connection.host)

                    HStack(spacing: 12) {
                        TextField("Username", text: $workspace.connection.username)

                        TextField("Port", value: $workspace.connection.port, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 92)
                    }

                    Picker("Authentication", selection: $workspace.connection.authenticationMode) {
                        ForEach(TermBridgeKitConnectionConfig.AuthenticationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(workspace.connection.authenticationMode.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if workspace.connection.authenticationMode == .password {
                        SecureField("Password", text: $workspace.connection.password)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Private Key")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $workspace.connection.privateKeyPEM)
                                .font(.caption.monospaced())
                                .frame(minHeight: 180)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.quaternary.opacity(0.18))
                                )
                        }
                    }

                    TextField("Startup Command", text: $workspace.connection.startupCommand, axis: .vertical)
                        .lineLimit(1...3)
                }
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Label(workspace.statusMessage, systemImage: statusSymbol)
                        .font(.subheadline)

                    if let size = workspace.terminalSize {
                        Text("Terminal size: \(size.columns)x\(size.rows)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let validationError = workspace.connection.validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let lastErrorMessage = workspace.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if workspace.didLoadEnvironmentConfiguration {
                        Text("Loaded from `TERMBRIDGEKIT_SSH_*` environment variables.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusSymbol: String {
        switch workspace.status {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "bolt.horizontal.circle.fill"
        case .disconnected:
            return "circle.dashed"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct DesktopTerminalPane: View {
    let workspace: TermBridgeKitSSHWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.connection.displayName)
                        .font(.headline)
                    Text(workspace.connection.endpointLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let size = workspace.terminalSize {
                    Text("\(size.columns)x\(size.rows)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            TermBridgeKitTerminalView(
                controller: workspace.controller,
                fontSize: 13
            )
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.08))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DesktopGuideScreen: View {
    let guide: TermBridgeKitConnectionGuide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(guide.title)
                    .font(.largeTitle.weight(.semibold))

                Text(guide.summary)
                    .foregroundStyle(.secondary)

                ForEach(guide.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)

                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.body)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }

                if let footer = guide.footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Guide")
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
