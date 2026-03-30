import Foundation

public struct TermBridgeKitConnectionGuide: Equatable, Sendable {
    public struct Section: Identifiable, Equatable, Sendable {
        public let id: String
        public var title: String
        public var items: [String]

        public init(id: String, title: String, items: [String]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    public var title: String
    public var summary: String
    public var sections: [Section]
    public var footer: String?

    public init(
        title: String,
        summary: String,
        sections: [Section],
        footer: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.sections = sections
        self.footer = footer
    }

    public static let sshStarter = Self(
        title: "SSH Starter Guide",
        summary: "This is the small reusable layer above the raw terminal surface. You define a connection, pick authentication, and the workspace manages the terminal session lifecycle for you.",
        sections: [
            Section(
                id: "connect",
                title: "Connect",
                items: [
                    "Enter a host, port, and username. The workspace turns that into the lower-level SSH configuration only when everything is valid.",
                    "Use a startup command when you want persistence. `tmux new -A -s termbridgekit` is a good default for app-like sessions."
                ]
            ),
            Section(
                id: "auth",
                title: "Authenticate",
                items: [
                    "Password mode is good for quick local testing.",
                    "Private key mode is what you will usually want in a real app.",
                    "If you set the `TERMBRIDGEKIT_SSH_*` environment variables in the demo, the workspace can preload the form and auto-connect."
                ]
            ),
            Section(
                id: "ship",
                title: "Ship It In Another App",
                items: [
                    "Keep `TermBridgeKit` responsible for rendering, input, clipboard, and raw SSH.",
                    "Use the starter workspace for connection state, reconnection, status copy, and setup guidance.",
                    "Layer styling and product-specific pairing flows on top when your app is ready."
                ]
            )
        ],
        footer: "The idea is that a new app should be able to copy the sample shape, swap in its own styling, and have a solid SSH terminal on day one."
    )
}
