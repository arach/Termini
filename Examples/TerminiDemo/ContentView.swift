#if os(macOS)
import SwiftUI
import Termini

struct ContentView: View {
    @State private var workspace = TerminiLocalPTYWorkspace()
    @State private var didStart = false
    @State private var terminalAppearance = TerminiTerminalAppearance(
        theme: .midnightBloom,
        fontSize: 13
    )

    var body: some View {
        VStack(spacing: 0) {
            header

            TerminiTerminalView(
                controller: workspace.controller,
                appearance: terminalAppearance
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .task {
            guard !didStart else { return }
            didStart = true
            workspace.start()
        }
        .onDisappear {
            workspace.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local PTY Demo")
                    .font(.headline)
                Text(workspace.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let size = workspace.terminalSize {
                Text("\(size.columns)x\(size.rows)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(workspace.isRunning ? "Stop" : "Start") {
                workspace.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
}
#endif
