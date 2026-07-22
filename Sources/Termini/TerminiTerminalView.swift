import SwiftUI

/// SwiftUI wrapper for the live Ghostty surface.
public struct TerminiTerminalView: View {
    private let controller: TerminiTerminalController?
    private let showsSystemKeyboard: Bool
    private let appearance: TerminiTerminalAppearance
    // render gate for warm-cached surfaces (see TerminiSurfaceView).
    private let isRenderVisible: Bool

    public init(
        controller: TerminiTerminalController? = nil,
        showsSystemKeyboard: Bool = true,
        appearance: TerminiTerminalAppearance = .default,
        isRenderVisible: Bool = true
    ) {
        self.controller = controller
        self.showsSystemKeyboard = showsSystemKeyboard
        self.appearance = appearance
        self.isRenderVisible = isRenderVisible
    }

    public init(
        controller: TerminiTerminalController? = nil,
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
        TerminiSurfaceView(
            controller: controller,
            showsSystemKeyboard: showsSystemKeyboard,
            appearance: appearance,
            isRenderVisible: isRenderVisible
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
