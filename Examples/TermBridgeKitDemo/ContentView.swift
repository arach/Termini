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
    @State private var showsAppearanceStudio = false
    @State private var terminalAppearance = TermBridgeKitTerminalAppearance(
        theme: .midnightBloom,
        fontSize: 13
    )

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
                DesktopConnectionScreen(
                    workspace: workspace,
                    terminalAppearance: $terminalAppearance,
                    showsAppearanceStudio: $showsAppearanceStudio
                )
            case .guide:
                DesktopGuideScreen(
                    guide: workspace.guide,
                    theme: terminalAppearance.theme ?? .midnightBloom
                )
            }
        }
        .sheet(isPresented: $showsAppearanceStudio) {
            DesktopAppearanceStudio(appearance: $terminalAppearance)
                .frame(minWidth: 700, minHeight: 680)
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
    @Binding var terminalAppearance: TermBridgeKitTerminalAppearance
    @Binding var showsAppearanceStudio: Bool

    private var theme: TermBridgeKitTerminalTheme {
        terminalAppearance.theme ?? .midnightBloom
    }

    var body: some View {
        HSplitView {
            DesktopConnectionInspector(
                workspace: workspace,
                theme: theme,
                terminalAppearance: terminalAppearance,
                openAppearanceStudio: {
                    showsAppearanceStudio = true
                }
            )
            .frame(minWidth: 340, idealWidth: 380, maxWidth: 430)

            DesktopTerminalPane(
                workspace: workspace,
                terminalAppearance: terminalAppearance,
                openAppearanceStudio: {
                    showsAppearanceStudio = true
                }
            )
        }
        .navigationTitle("SSH Starter")
        .background(theme.screenGradient.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Appearance", systemImage: "paintbrush.pointed") {
                    showsAppearanceStudio = true
                }

                Button(workspace.isConnected ? "Disconnect" : "Connect") {
                    Task {
                        await workspace.toggleConnection()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!workspace.isConnected && !workspace.canConnect)
            }
        }
    }
}

private struct DesktopConnectionInspector: View {
    @Bindable var workspace: TermBridgeKitSSHWorkspace
    let theme: TermBridgeKitTerminalTheme
    let terminalAppearance: TermBridgeKitTerminalAppearance
    let openAppearanceStudio: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connection")
                                .font(.title2.weight(.semibold))
                            Text("Shape the SSH session on the left, then tune the terminal look and feel from the appearance studio.")
                                .foregroundStyle(theme.mutedForegroundColor)
                        }

                        Spacer()

                        Button("Appearance", systemImage: "slider.horizontal.3") {
                            openAppearanceStudio()
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accentColor)
                    }

                    HStack(spacing: 10) {
                        DemoPill(label: theme.name, icon: "sparkles", tint: theme.accentColor)
                        DemoPill(
                            label: "\(formattedFontSize) pt",
                            icon: "textformat.size",
                            tint: theme.secondaryAccentColor
                        )
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
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
                        .foregroundStyle(theme.mutedForegroundColor)

                    if workspace.connection.authenticationMode == .password {
                        SecureField("Password", text: $workspace.connection.password)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Private Key")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.mutedForegroundColor)

                            TextEditor(text: $workspace.connection.privateKeyPEM)
                                .font(.caption.monospaced())
                                .frame(minHeight: 180)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(theme.editorBackground)
                                )
                        }
                    }

                    TextField("Startup Command", text: $workspace.connection.startupCommand, axis: .vertical)
                        .lineLimit(1...3)
                }
                .textFieldStyle(.roundedBorder)
                .padding(22)
                .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(workspace.statusMessage, systemImage: statusSymbol)
                        .font(.subheadline.weight(.medium))

                    if let size = workspace.terminalSize {
                        Text("Terminal size: \(size.columns)x\(size.rows)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(theme.mutedForegroundColor)
                    }

                    if let validationError = workspace.connection.validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let lastErrorMessage = workspace.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.mutedForegroundColor)
                    }

                    if workspace.didLoadEnvironmentConfiguration {
                        Text("Loaded from `TERMBRIDGEKIT_SSH_*` environment variables.")
                            .font(.caption)
                            .foregroundStyle(theme.mutedForegroundColor)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(.clear)
    }

    private var formattedFontSize: String {
        String(format: "%.1f", terminalAppearance.fontSize ?? 13)
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
    let terminalAppearance: TermBridgeKitTerminalAppearance
    let openAppearanceStudio: () -> Void

    private var theme: TermBridgeKitTerminalTheme {
        terminalAppearance.theme ?? .midnightBloom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspace.connection.displayName)
                        .font(.title3.weight(.semibold))
                    Text(workspace.connection.endpointLabel)
                        .font(.subheadline)
                        .foregroundStyle(theme.mutedForegroundColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if let size = workspace.terminalSize {
                        DemoPill(
                            label: "\(size.columns)x\(size.rows)",
                            icon: "rectangle.split.3x1",
                            tint: theme.accentColor
                        )
                    }

                    Button("Studio", systemImage: "wand.and.stars") {
                        openAppearanceStudio()
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.secondaryAccentColor)
                }
            }

            VStack(spacing: 0) {
                HStack {
                    ThemeTrafficLights(accent: theme.accentColor)
                    Spacer()
                    Text(theme.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.mutedForegroundColor)
                    Spacer()
                    Text("Font \(String(format: "%.1f", terminalAppearance.fontSize ?? 13))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.mutedForegroundColor)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(theme.terminalHeaderBackground)

                TermBridgeKitTerminalView(
                    controller: workspace.controller,
                    appearance: terminalAppearance
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(theme.surfaceStroke, lineWidth: 1)
            }
            .shadow(color: theme.shadowColor, radius: 32, y: 18)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(theme.terminalShellBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 34)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                }
                .padding(20)
        )
    }
}

private struct DesktopAppearanceStudio: View {
    @Binding var appearance: TermBridgeKitTerminalAppearance

    private let fontSizeStops: [Double] = [11, 12, 13, 14, 15, 16, 18]

    var body: some View {
        let selectedTheme = Binding<TermBridgeKitTerminalTheme>(
            get: { appearance.theme ?? .midnightBloom },
            set: { appearance.theme = $0 }
        )
        let fontSize = Binding<Double>(
            get: { appearance.fontSize ?? 13 },
            set: { appearance.fontSize = $0 }
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppearanceStudioHeader(
                    theme: selectedTheme.wrappedValue,
                    fontSize: fontSize.wrappedValue
                )

                HStack(alignment: .top, spacing: 22) {
                    AppearancePreviewColumn(
                        theme: selectedTheme.wrappedValue,
                        fontSize: fontSize.wrappedValue
                    )
                    .frame(width: 260)

                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Theme Library")
                                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    Text("Pick a palette with a clear mood and apply it to the live terminal immediately.")
                                        .foregroundStyle(selectedTheme.wrappedValue.mutedForegroundColor)
                                }

                                Spacer()

                                Text("\(TermBridgeKitTerminalTheme.presets.count) presets")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedTheme.wrappedValue.accentColor.opacity(0.14), in: Capsule())
                                    .foregroundStyle(selectedTheme.wrappedValue.accentColor)
                            }

                            ThemeGroupSection(
                                title: "Dark Themes",
                                subtitle: "Immersive palettes for focused terminal work.",
                                themes: TermBridgeKitTerminalTheme.presets.filter { $0.colorScheme == .dark },
                                selectedTheme: selectedTheme
                            )

                            ThemeGroupSection(
                                title: "Light Themes",
                                subtitle: "Bright surfaces that still keep terminal contrast crisp.",
                                themes: TermBridgeKitTerminalTheme.presets.filter { $0.colorScheme == .light },
                                selectedTheme: selectedTheme
                            )
                        }
                        .padding(22)
                        .background(selectedTheme.wrappedValue.panelBackground, in: RoundedRectangle(cornerRadius: 28))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(selectedTheme.wrappedValue.cardStroke, lineWidth: 1)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Type Scale")
                                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    Text("Tune terminal density without losing readability.")
                                        .foregroundStyle(selectedTheme.wrappedValue.mutedForegroundColor)
                                }

                                Spacer()

                                Text("\(String(format: "%.1f", fontSize.wrappedValue)) pt")
                                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selectedTheme.wrappedValue.accentColor.opacity(0.14), in: Capsule())
                                    .foregroundStyle(selectedTheme.wrappedValue.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Slider(value: fontSize, in: 10...20, step: 0.5)
                                    .tint(selectedTheme.wrappedValue.accentColor)

                                HStack {
                                    Text("10 pt")
                                    Spacer()
                                    Text("20 pt")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedTheme.wrappedValue.mutedForegroundColor)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                                ForEach(fontSizeStops, id: \.self) { stop in
                                    FontSizeChip(
                                        value: stop,
                                        isSelected: abs(fontSize.wrappedValue - stop) < 0.05,
                                        theme: selectedTheme.wrappedValue
                                    ) {
                                        fontSize.wrappedValue = stop
                                    }
                                }
                            }

                            Text("Changes apply live to the current terminal surface, so the studio behaves like a real settings panel instead of a disconnected mockup.")
                                .font(.caption)
                                .foregroundStyle(selectedTheme.wrappedValue.mutedForegroundColor)
                        }
                        .padding(22)
                        .background(selectedTheme.wrappedValue.panelBackground, in: RoundedRectangle(cornerRadius: 28))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(selectedTheme.wrappedValue.cardStroke, lineWidth: 1)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Profiles")
                                .font(.headline)
                            Text("The appearance model is now in the right shape for richer profiles. Theme files and font-family support can plug into the same `TermBridgeKitTerminalAppearance` surface once that runtime capability is exposed cleanly.")
                                .foregroundStyle(selectedTheme.wrappedValue.mutedForegroundColor)
                        }
                        .padding(20)
                        .background(selectedTheme.wrappedValue.cardBackground, in: RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(selectedTheme.wrappedValue.cardStroke, lineWidth: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
        .background((appearance.theme ?? .midnightBloom).screenGradient.ignoresSafeArea())
    }
}

private struct AppearanceStudioHeader: View {
    let theme: TermBridgeKitTerminalTheme
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance Studio")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("Tune the terminal like a product surface with stronger visual themes, clearer hierarchy, and type that feels intentionally chosen.")
                        .foregroundStyle(theme.mutedForegroundColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("LIVE")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(theme.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(theme.accentColor)

                    Text("Applied to the current session")
                        .font(.caption)
                        .foregroundStyle(theme.mutedForegroundColor)
                }
            }

            HStack(spacing: 10) {
                DemoPill(label: theme.name, icon: "sparkles", tint: theme.accentColor)
                DemoPill(label: theme.schemeLabel, icon: "circle.lefthalf.filled", tint: theme.secondaryAccentColor)
                DemoPill(
                    label: "\(String(format: "%.1f", fontSize)) pt",
                    icon: "textformat.size",
                    tint: theme.accentColor.opacity(0.92)
                )
            }
        }
        .padding(24)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        }
    }
}

private struct AppearancePreviewColumn: View {
    let theme: TermBridgeKitTerminalTheme
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.title3.weight(.semibold))
                Text(theme.studioDescription)
                    .font(.callout)
                    .foregroundStyle(theme.mutedForegroundColor)
            }

            ThemePreviewTerminal(
                theme: theme,
                fontSize: fontSize
            )
            .frame(height: 270)

            VStack(alignment: .leading, spacing: 12) {
                AppearanceMetricRow(
                    label: "Cursor",
                    value: theme.cursor.hexLabel,
                    tint: theme.accentColor
                )
                AppearanceMetricRow(
                    label: "Selection",
                    value: (theme.selectionBackground ?? theme.background).hexLabel,
                    tint: Color(terminalColor: theme.selectionBackground ?? theme.background)
                )
                AppearanceMetricRow(
                    label: "Foreground",
                    value: theme.foreground.hexLabel,
                    tint: theme.foregroundColor
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Palette")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.mutedForegroundColor)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], spacing: 8) {
                    ForEach(Array(theme.ansiPalette.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(terminalColor: color))
                            .frame(height: 24)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(theme.cardStroke, lineWidth: 0.5)
                            }
                    }
                }
            }
        }
        .padding(22)
        .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        }
    }
}

private struct ThemeGroupSection: View {
    let title: String
    let subtitle: String
    let themes: [TermBridgeKitTerminalTheme]
    let selectedTheme: Binding<TermBridgeKitTerminalTheme>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(selectedTheme.wrappedValue.mutedForegroundColor)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                ForEach(themes) { theme in
                    ThemeOptionCard(
                        theme: theme,
                        isSelected: selectedTheme.wrappedValue == theme
                    ) {
                        selectedTheme.wrappedValue = theme
                    }
                }
            }
        }
    }
}

private struct AppearanceMetricRow: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 12, height: 12)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

private struct FontSizeChip: View {
    let value: Double
    let isSelected: Bool
    let theme: TermBridgeKitTerminalTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(format: "%.0f", value))
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(theme.cardBackground)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(theme.accentColor.opacity(0.18))
                            }
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? theme.accentColor : theme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
                }
                .foregroundStyle(isSelected ? theme.accentColor : theme.foregroundColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set font size to \(String(format: "%.0f", value)) points")
    }
}

private struct ThemeOptionCard: View {
    let theme: TermBridgeKitTerminalTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(theme.schemeLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(theme.secondaryAccentColor)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? theme.accentColor : .secondary)
                }

                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.terminalShellBackground)
                    .overlay {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                ForEach(Array(theme.ansiPalette.prefix(6).enumerated()), id: \.offset) { _, color in
                                    Circle()
                                        .fill(Color(terminalColor: color))
                                        .frame(width: 10, height: 10)
                                }
                                Spacer()
                            }

                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.backgroundColor)
                                .overlay(alignment: .topLeading) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("$ ssh product@host")
                                            .foregroundStyle(theme.accentColor)
                                        Text(theme.sampleCommand)
                                        Text(theme.studioDescription)
                                            .foregroundStyle(theme.mutedForegroundColor)
                                            .lineLimit(2)
                                    }
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                        }
                        .padding(12)
                    }
                    .frame(height: 130)

                VStack(alignment: .leading, spacing: 6) {
                    Text(theme.name)
                        .font(.headline)
                    Text(theme.studioTagline)
                        .font(.caption)
                        .foregroundStyle(theme.mutedForegroundColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(isSelected ? theme.accentColor : theme.cardStroke, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Theme \(theme.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ThemePreviewTerminal: View {
    let theme: TermBridgeKitTerminalTheme
    let fontSize: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ThemeTrafficLights(accent: theme.accentColor)
                Spacer()
                VStack(spacing: 2) {
                    Text(theme.name)
                        .font(.caption.weight(.semibold))
                    Text("Live session preview")
                        .font(.caption2)
                }
                .foregroundStyle(theme.mutedForegroundColor)
                Spacer()
                Text("\(String(format: "%.1f", fontSize)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.mutedForegroundColor)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(theme.terminalHeaderBackground)

            VStack(alignment: .leading, spacing: 10) {
                Text("product@edge:~ $ termbridge preview")
                    .foregroundStyle(theme.accentColor)
                Text("Applying terminal appearance profile")
                Text(theme.sampleCommand)
                    .foregroundStyle(theme.secondaryAccentColor)
                Text("font-size \(String(format: "%.1f", fontSize))")
                    .foregroundStyle(theme.mutedForegroundColor)

                HStack(spacing: 8) {
                    ForEach(Array(theme.ansiPalette.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(terminalColor: color))
                            .frame(width: 22, height: 18)
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                theme.backgroundColor
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(theme.accentColor.opacity(0.12))
                            .frame(width: 160, height: 160)
                            .blur(radius: 12)
                            .offset(x: 36, y: 40)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
        }
    }
}

private struct ThemeTrafficLights: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.32))
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
            Circle().fill(accent)
        }
        .frame(height: 12)
    }
}

private struct DemoPill: View {
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct DesktopGuideScreen: View {
    let guide: TermBridgeKitConnectionGuide
    let theme: TermBridgeKitTerminalTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(guide.title)
                    .font(.largeTitle.weight(.semibold))

                Text(guide.summary)
                    .foregroundStyle(theme.mutedForegroundColor)

                ForEach(guide.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)

                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(theme.mutedForegroundColor)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.body)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(theme.cardStroke, lineWidth: 1)
                    }
                }

                if let footer = guide.footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(theme.mutedForegroundColor)
                }
            }
            .padding(24)
        }
        .navigationTitle("Guide")
        .background(theme.screenGradient.ignoresSafeArea())
    }
}

private extension TermBridgeKitTerminalTheme {
    var schemeLabel: String {
        colorScheme == .dark ? "Dark" : "Light"
    }

    var studioTagline: String {
        switch id {
        case "midnight-bloom":
            return "Deep indigo contrast with a warm cursor accent."
        case "ember-glow":
            return "Smoky charcoal and ember tones with richer warmth."
        case "jade-night":
            return "Cool blue-greens with a crisp terminal glow."
        case "paper-lantern":
            return "Soft paper tones for brighter day-time sessions."
        case "blueprint":
            return "Airy drafting-table blues with clean technical contrast."
        default:
            return "A balanced terminal palette for product-ready surfaces."
        }
    }

    var studioDescription: String {
        switch id {
        case "midnight-bloom":
            return "Confident, cinematic, and great for darker control-room layouts."
        case "ember-glow":
            return "A warmer dark mode that feels tactile instead of flat."
        case "jade-night":
            return "Sharper and cooler, with a calmer operational tone."
        case "paper-lantern":
            return "A softer light theme that keeps command output approachable."
        case "blueprint":
            return "Bright and technical, like a polished engineering workspace."
        default:
            return "Polished terminal appearance tuned for readability."
        }
    }

    var sampleCommand: String {
        "theme \(id)"
    }

    var backgroundColor: Color {
        Color(terminalColor: background)
    }

    var foregroundColor: Color {
        Color(terminalColor: foreground)
    }

    var accentColor: Color {
        Color(terminalColor: cursor)
    }

    var secondaryAccentColor: Color {
        Color(terminalColor: ansiPalette[4])
    }

    var mutedForegroundColor: Color {
        foregroundColor.opacity(colorScheme == .dark ? 0.72 : 0.78)
    }

    var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var surfaceStroke: Color {
        accentColor.opacity(colorScheme == .dark ? 0.55 : 0.4)
    }

    var shadowColor: Color {
        backgroundColor.opacity(colorScheme == .dark ? 0.34 : 0.18)
    }

    var editorBackground: Color {
        colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.82)
    }

    var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [backgroundColor.opacity(0.88), Color.white.opacity(0.04)]
                : [Color.white.opacity(0.94), backgroundColor.opacity(0.74)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var panelBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.06), backgroundColor.opacity(0.94)]
                : [Color.white.opacity(0.98), backgroundColor.opacity(0.78)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var terminalShellBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [backgroundColor.opacity(0.98), Color(terminalColor: ansiPalette[0]).opacity(0.96)]
                : [Color.white.opacity(0.98), backgroundColor.opacity(0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var terminalHeaderBackground: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.04)
    }

    var screenGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(terminalColor: ansiPalette[0]).opacity(0.96),
                    backgroundColor.opacity(0.98),
                    accentColor.opacity(0.18)
                ]
                : [
                    Color.white.opacity(0.98),
                    backgroundColor.opacity(0.96),
                    secondaryAccentColor.opacity(0.18)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension Color {
    init(terminalColor: TermBridgeKitTerminalColor) {
        self.init(
            red: Double(terminalColor.red) / 255.0,
            green: Double(terminalColor.green) / 255.0,
            blue: Double(terminalColor.blue) / 255.0
        )
    }
}

private extension TermBridgeKitTerminalColor {
    var hexLabel: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}
