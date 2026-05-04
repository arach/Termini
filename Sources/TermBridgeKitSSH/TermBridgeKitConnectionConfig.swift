import TermBridgeKit
import Foundation

public struct TermBridgeKitConnectionConfig: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case name
        case host
        case port
        case username
        case authenticationMode
        case password
        case privateKeyPEM
        case term
        case startupCommand
        case hostKeyPolicy
        case hostKeyFingerprint
    }

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
    public var hostKeyPolicy: TermBridgeKitSSHHostKeyPolicy
    public var hostKeyFingerprint: String

    public init(
        name: String = "Primary Mac",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authenticationMode: AuthenticationMode = .privateKey,
        password: String = "",
        privateKeyPEM: String = "",
        term: String = "xterm-256color",
        startupCommand: String = "",
        hostKeyPolicy: TermBridgeKitSSHHostKeyPolicy = .trustOnFirstUse,
        hostKeyFingerprint: String = ""
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
        self.hostKeyPolicy = hostKeyPolicy
        self.hostKeyFingerprint = hostKeyFingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Primary Mac"
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.authenticationMode = try container.decodeIfPresent(AuthenticationMode.self, forKey: .authenticationMode) ?? .privateKey
        self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        self.privateKeyPEM = try container.decodeIfPresent(String.self, forKey: .privateKeyPEM) ?? ""
        self.term = try container.decodeIfPresent(String.self, forKey: .term) ?? "xterm-256color"
        self.startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand) ?? ""
        self.hostKeyPolicy = try container.decodeIfPresent(TermBridgeKitSSHHostKeyPolicy.self, forKey: .hostKeyPolicy) ?? .trustOnFirstUse
        self.hostKeyFingerprint = try container.decodeIfPresent(String.self, forKey: .hostKeyFingerprint) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(authenticationMode, forKey: .authenticationMode)
        try container.encode(password, forKey: .password)
        try container.encode(privateKeyPEM, forKey: .privateKeyPEM)
        try container.encode(term, forKey: .term)
        try container.encode(startupCommand, forKey: .startupCommand)
        try container.encode(hostKeyPolicy, forKey: .hostKeyPolicy)
        try container.encode(hostKeyFingerprint, forKey: .hostKeyFingerprint)
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
            startupCommand: nonEmpty(startupCommand),
            hostKeyPolicy: hostKeyPolicy,
            hostKeyFingerprint: nonEmpty(hostKeyFingerprint)
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

        let hostKeyPolicy = TermBridgeKitSSHHostKeyPolicy(
            rawValue: nonEmpty(environment["TERMBRIDGEKIT_SSH_HOST_KEY_POLICY"]) ?? ""
        ) ?? .trustOnFirstUse

        return Self(
            name: nonEmpty(environment["TERMBRIDGEKIT_SSH_NAME"]) ?? "Demo SSH Host",
            host: host,
            port: Int(environment["TERMBRIDGEKIT_SSH_PORT"] ?? "") ?? 22,
            username: username,
            authenticationMode: privateKey.isEmpty ? .password : .privateKey,
            password: password,
            privateKeyPEM: privateKey,
            term: nonEmpty(environment["TERMBRIDGEKIT_SSH_TERM"]) ?? "xterm-256color",
            startupCommand: nonEmpty(environment["TERMBRIDGEKIT_SSH_COMMAND"]) ?? "tmux new -A -s termbridgekit",
            hostKeyPolicy: hostKeyPolicy,
            hostKeyFingerprint: nonEmpty(environment["TERMBRIDGEKIT_SSH_HOST_KEY_FINGERPRINT"]) ?? ""
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
