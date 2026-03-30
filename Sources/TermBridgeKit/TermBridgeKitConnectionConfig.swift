import Foundation

public struct TermBridgeKitConnectionConfig: Codable, Equatable, Sendable {
    public enum AuthenticationMode: String, CaseIterable, Codable, Identifiable, Sendable {
        case password
        case privateKey

        public var id: Self { self }

        public var title: String {
            switch self {
            case .password:
                return "Password"
            case .privateKey:
                return "Private Key"
            }
        }

        public var guidance: String {
            switch self {
            case .password:
                return "Use a login password for quick tests and local demos."
            case .privateKey:
                return "Use an SSH private key for the more typical app setup."
            }
        }
    }

    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authenticationMode: AuthenticationMode
    public var password: String
    public var privateKeyPEM: String
    public var term: String
    public var startupCommand: String

    public init(
        name: String = "Primary Mac",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authenticationMode: AuthenticationMode = .privateKey,
        password: String = "",
        privateKeyPEM: String = "",
        term: String = "xterm-256color",
        startupCommand: String = ""
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authenticationMode = authenticationMode
        self.password = password
        self.privateKeyPEM = privateKeyPEM
        self.term = term
        self.startupCommand = startupCommand
    }

    public var displayName: String {
        nonEmpty(name) ?? "SSH Connection"
    }

    public var endpointLabel: String {
        let trimmedUsername = nonEmpty(username)
        let trimmedHost = nonEmpty(host)

        switch (trimmedUsername, trimmedHost) {
        case let (.some(username), .some(host)):
            return "\(username)@\(host):\(port)"
        case let (.none, .some(host)):
            return "\(host):\(port)"
        case let (.some(username), .none):
            return username
        case (.none, .none):
            return displayName
        }
    }

    public var credentialSummary: String {
        switch authenticationMode {
        case .password:
            return "Password"
        case .privateKey:
            return "Private Key"
        }
    }

    public var validationError: String? {
        guard nonEmpty(host) != nil else {
            return "Enter an SSH host."
        }

        guard port > 0 else {
            return "Enter a valid SSH port."
        }

        guard nonEmpty(username) != nil else {
            return "Enter an SSH username."
        }

        switch authenticationMode {
        case .password:
            guard nonEmpty(password) != nil else {
                return "Enter a password."
            }
        case .privateKey:
            guard nonEmpty(privateKeyPEM) != nil else {
                return "Paste an SSH private key."
            }
        }

        return nil
    }

    public var isReadyToConnect: Bool {
        validationError == nil
    }

    public func resolvedSSHConfiguration() -> TermBridgeKitSSHConfiguration? {
        guard validationError == nil else { return nil }

        return TermBridgeKitSSHConfiguration(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: authenticationMode == .password ? password.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            privateKeyPEM: authenticationMode == .privateKey ? normalizedPrivateKey(privateKeyPEM) : nil,
            term: nonEmpty(term) ?? "xterm-256color",
            startupCommand: nonEmpty(startupCommand)
        )
    }

    public static func demoEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self? {
        guard let host = nonEmpty(environment["TERMBRIDGEKIT_SSH_HOST"]),
              let username = nonEmpty(environment["TERMBRIDGEKIT_SSH_USER"])
        else {
            return nil
        }

        let password = nonEmpty(environment["TERMBRIDGEKIT_SSH_PASSWORD"]) ?? ""
        let privateKey = nonEmpty(environment["TERMBRIDGEKIT_SSH_PRIVATE_KEY"])?
            .replacingOccurrences(of: "\\n", with: "\n") ?? ""

        guard !password.isEmpty || !privateKey.isEmpty else {
            return nil
        }

        return Self(
            name: nonEmpty(environment["TERMBRIDGEKIT_SSH_NAME"]) ?? "Demo SSH Host",
            host: host,
            port: Int(environment["TERMBRIDGEKIT_SSH_PORT"] ?? "") ?? 22,
            username: username,
            authenticationMode: privateKey.isEmpty ? .password : .privateKey,
            password: password,
            privateKeyPEM: privateKey,
            term: nonEmpty(environment["TERMBRIDGEKIT_SSH_TERM"]) ?? "xterm-256color",
            startupCommand: nonEmpty(environment["TERMBRIDGEKIT_SSH_COMMAND"]) ?? "tmux new -A -s termbridgekit"
        )
    }

    private func normalizedPrivateKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func nonEmpty(_ value: String) -> String? {
        Self.nonEmpty(value)
    }
}
