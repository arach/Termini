import SwiftUI

/// SwiftUI wrapper for the live Ghostty surface.
public struct TermBridgeKitTerminalView: View {
    private let controller: TermBridgeKitTerminalController?
    private let showsSystemKeyboard: Bool
    private let appearance: TermBridgeKitTerminalAppearance

    public init(
        controller: TermBridgeKitTerminalController? = nil,
        showsSystemKeyboard: Bool = true,
        appearance: TermBridgeKitTerminalAppearance = .default
    ) {
        self.controller = controller
        self.showsSystemKeyboard = showsSystemKeyboard
        self.appearance = appearance
    }

    public init(
        controller: TermBridgeKitTerminalController? = nil,
        showsSystemKeyboard: Bool = true,
        fontSize: Double? = nil
    ) {
        self.init(
            controller: controller,
            showsSystemKeyboard: showsSystemKeyboard,
            appearance: .init(fontSize: fontSize)
        )
    }

    public var body: some View {
        TermBridgeKitSurfaceView(
            controller: controller,
            showsSystemKeyboard: showsSystemKeyboard,
            appearance: appearance
        )
            .background(terminalBackground)
    }

    private var terminalBackground: Color {
        guard let theme = appearance.theme else {
            return .black
        }

        return Color(
            red: Double(theme.background.red) / 255.0,
            green: Double(theme.background.green) / 255.0,
            blue: Double(theme.background.blue) / 255.0
        )
    }
}
