import SwiftUI

/// SwiftUI wrapper for the live Ghostty surface.
public struct TermBridgeKitTerminalView: View {
    private let controller: TermBridgeKitTerminalController?
    private let showsSystemKeyboard: Bool
    private let fontSize: Double?

    public init(
        controller: TermBridgeKitTerminalController? = nil,
        showsSystemKeyboard: Bool = true,
        fontSize: Double? = nil
    ) {
        self.controller = controller
        self.showsSystemKeyboard = showsSystemKeyboard
        self.fontSize = fontSize
    }

    public var body: some View {
        TermBridgeKitSurfaceView(
            controller: controller,
            showsSystemKeyboard: showsSystemKeyboard,
            fontSize: fontSize
        )
            .background(.black)
    }
}
