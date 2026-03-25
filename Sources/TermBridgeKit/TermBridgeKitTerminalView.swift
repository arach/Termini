import SwiftUI

/// SwiftUI wrapper for the live Ghostty surface.
public struct TermBridgeKitTerminalView: View {
    private let controller: TermBridgeKitTerminalController?
    private let showsSystemKeyboard: Bool

    public init(
        controller: TermBridgeKitTerminalController? = nil,
        showsSystemKeyboard: Bool = true
    ) {
        self.controller = controller
        self.showsSystemKeyboard = showsSystemKeyboard
    }

    public var body: some View {
        TermBridgeKitSurfaceView(
            controller: controller,
            showsSystemKeyboard: showsSystemKeyboard
        )
            .background(.black)
    }
}
