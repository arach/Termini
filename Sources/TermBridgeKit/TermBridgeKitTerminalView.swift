import SwiftUI

/// SwiftUI wrapper for the live Ghostty surface.
public struct TermBridgeKitTerminalView: View {
    private let controller: TermBridgeKitTerminalController?

    public init(controller: TermBridgeKitTerminalController? = nil) {
        self.controller = controller
    }

    public var body: some View {
        TermBridgeKitSurfaceView(controller: controller)
            .background(.black)
    }
}
