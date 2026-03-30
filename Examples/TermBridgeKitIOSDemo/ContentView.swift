import SwiftUI
import TermBridgeKit

struct ContentView: View {
    @State private var workspace = TermBridgeKitSSHWorkspace(
        connection: .init(startupCommand: "tmux new -A -s termbridgekit")
    )
    @State private var didBootstrap = false
    @State private var showsGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TerminalPreviewCard(workspace: workspace)
                    ConnectionConfigurationCard(workspace: workspace)
                    GuidePreviewCard(
                        guide: workspace.guide,
                        showsGuide: $showsGuide
                    )
                }
                .padding()
                .padding(.bottom, 92)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SSH Starter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guide", systemImage: "book.closed") {
                        showsGuide = true
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ConnectBar(workspace: workspace)
            }
            .sheet(isPresented: $showsGuide) {
                NavigationStack {
                    GuideDetailScreen(guide: workspace.guide)
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
}

private struct TerminalPreviewCard: View {
    let workspace: TermBridgeKitSSHWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.connection.displayName)
                        .font(.headline)
                    Text(workspace.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let size = workspace.terminalSize {
                    Text("\(size.columns)x\(size.rows)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            GeometryReader { proxy in
                TermBridgeKitTerminalView(
                    controller: workspace.controller,
                    fontSize: preferredFontSize(for: proxy.size)
                )
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.08))
                }
            }
            .frame(height: 320)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func preferredFontSize(for size: CGSize) -> Double {
        let width = max(size.width, 260)
        let height = max(size.height, 220)
        let isLandscape = width > height

        let targetColumns = isLandscape ? 88.0 : 52.0
        let targetRows = isLandscape ? 24.0 : 18.0

        let widthLimitedSize = width / (targetColumns * 0.76)
        let heightLimitedSize = height / (targetRows * 1.62)
        let raw = min(widthLimitedSize, heightLimitedSize)
        let clamped = min(max(raw, 8.0), 12.0)
        return (clamped * 2).rounded() / 2
    }
}

private struct ConnectionConfigurationCard: View {
    @Bindable var workspace: TermBridgeKitSSHWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection")
                        .font(.headline)
                    Text("This is the reusable layer above raw SSH. Define a host once and let the workspace manage the session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if workspace.didLoadEnvironmentConfiguration {
                    Text("Loaded from env")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("Connection Name", text: $workspace.connection.name)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)

                TextField("Host", text: $workspace.connection.host)
                    .textInputAutocapitalization(.never)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    TextField("Username", text: $workspace.connection.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    TextField("Port", value: $workspace.connection.port, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
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
                        .textFieldStyle(.roundedBorder)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private Key")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $workspace.connection.privateKeyPEM)
                            .font(.caption.monospaced())
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.quaternary.opacity(0.18))
                            )
                    }
                }

                TextField("Startup Command", text: $workspace.connection.startupCommand, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if let validationError = workspace.connection.validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Label("Ready for \(workspace.connection.credentialSummary.lowercased()) authentication at \(workspace.connection.endpointLabel).", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let lastErrorMessage = workspace.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct GuidePreviewCard: View {
    let guide: TermBridgeKitConnectionGuide
    @Binding var showsGuide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guide.title)
                .font(.headline)
            Text(guide.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Open Setup Guide", systemImage: "arrow.up.right.square") {
                showsGuide = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct ConnectBar: View {
    let workspace: TermBridgeKitSSHWorkspace

    var body: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.connection.endpointLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(workspace.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(workspace.isConnected ? "Disconnect" : "Connect") {
                    Task {
                        await workspace.toggleConnection()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!workspace.isConnected && !workspace.canConnect)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

private struct GuideDetailScreen: View {
    let guide: TermBridgeKitConnectionGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(guide.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)

                ForEach(guide.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)

                        ForEach(section.items, id: \.self) { item in
                            Label(item, systemImage: "circle.fill")
                                .labelStyle(GuideItemLabelStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                }

                if let footer = guide.footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(guide.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct GuideItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            configuration.title
                .font(.subheadline)
        }
    }
}
