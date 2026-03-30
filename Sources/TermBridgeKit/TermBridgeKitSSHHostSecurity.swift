import CryptoKit
import Foundation
@preconcurrency import NIOSSH

public enum TermBridgeKitSSHHostKeyPolicy: String, CaseIterable, Codable, Sendable {
    case trustOnFirstUse
    case requireStoredHostKey
    case acceptAny

    public var title: String {
        switch self {
        case .trustOnFirstUse:
            return "Trust On First Use"
        case .requireStoredHostKey:
            return "Require Stored Host Key"
        case .acceptAny:
            return "Accept Any Host Key"
        }
    }

    public var guidance: String {
        switch self {
        case .trustOnFirstUse:
            return "Trust the first fingerprint you see, then reject future changes."
        case .requireStoredHostKey:
            return "Only connect when the host was already trusted before."
        case .acceptAny:
            return "Skip host verification. Use only for disposable local testing."
        }
    }
}

struct TermBridgeKitKnownHostKey: Equatable, Sendable {
    let algorithm: String
    let openSSHPublicKey: String
    let fingerprint: String

    init(hostKey: NIOSSHPublicKey) throws {
        let openSSHPublicKey = String(openSSHPublicKey: hostKey)
        let components = openSSHPublicKey.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)

        guard components.count >= 2,
              let rawKey = Data(base64Encoded: String(components[1])) else {
            throw TermBridgeKitSSHHostKeyValidationError.invalidHostKey
        }

        let digest = SHA256.hash(data: rawKey)
        let base64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")

        self.algorithm = String(components[0])
        self.openSSHPublicKey = openSSHPublicKey
        self.fingerprint = "SHA256:\(base64)"
    }
}

enum TermBridgeKitSSHHostKeyValidationError: LocalizedError, Equatable, Sendable {
    case invalidHostKey
    case unknownHost(host: String, port: Int, fingerprint: String)
    case changedHostKey(host: String, port: Int, expected: String, presented: String)
    case fingerprintMismatch(expected: String, presented: String)

    var errorDescription: String? {
        switch self {
        case .invalidHostKey:
            return "The SSH server presented an unreadable host key."
        case .unknownHost(let host, let port, let fingerprint):
            return "The host \(host):\(port) is not trusted yet. Presented fingerprint: \(fingerprint)"
        case .changedHostKey(let host, let port, let expected, let presented):
            return "The host key for \(host):\(port) changed. Expected \(expected), got \(presented)."
        case .fingerprintMismatch(let expected, let presented):
            return "The host fingerprint did not match. Expected \(expected), got \(presented)."
        }
    }
}

final class TermBridgeKitSSHKnownHostsStore: @unchecked Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let host: String
        let port: Int
        let algorithm: String
        let fingerprint: String
        let openSSHPublicKey: String
        let addedAt: Date
        var lastSeenAt: Date

        var id: String { "\(host):\(port)" }
    }

    enum ValidationResult: Equatable, Sendable {
        case trustedNewHost(Entry)
        case matchedStoredHost(Entry)
        case matchedPinnedFingerprint(String)
        case bypassed
    }

    static let shared = TermBridgeKitSSHKnownHostsStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "TermBridgeKit.SSHKnownHosts"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func entry(for host: String, port: Int) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return loadAll()[hostKey(host: host, port: port)]
    }

    @discardableResult
    func validate(
        presentedKey: TermBridgeKitKnownHostKey,
        host: String,
        port: Int,
        policy: TermBridgeKitSSHHostKeyPolicy,
        pinnedFingerprint: String?
    ) throws -> ValidationResult {
        let normalizedHost = normalizeHost(host)
        let normalizedPinnedFingerprint = Self.normalizeFingerprint(pinnedFingerprint)

        if let normalizedPinnedFingerprint {
            guard normalizedPinnedFingerprint == presentedKey.fingerprint else {
                throw TermBridgeKitSSHHostKeyValidationError.fingerprintMismatch(
                    expected: normalizedPinnedFingerprint,
                    presented: presentedKey.fingerprint
                )
            }
            return .matchedPinnedFingerprint(presentedKey.fingerprint)
        }

        switch policy {
        case .acceptAny:
            return .bypassed
        case .requireStoredHostKey:
            return try validateExistingHost(
                presentedKey: presentedKey,
                host: normalizedHost,
                port: port,
                allowTrustOnFirstUse: false
            )
        case .trustOnFirstUse:
            return try validateExistingHost(
                presentedKey: presentedKey,
                host: normalizedHost,
                port: port,
                allowTrustOnFirstUse: true
            )
        }
    }

    private func validateExistingHost(
        presentedKey: TermBridgeKitKnownHostKey,
        host: String,
        port: Int,
        allowTrustOnFirstUse: Bool
    ) throws -> ValidationResult {
        lock.lock()
        defer { lock.unlock() }

        var entries = loadAll()
        let key = hostKey(host: host, port: port)

        if var existing = entries[key] {
            guard existing.fingerprint == presentedKey.fingerprint else {
                throw TermBridgeKitSSHHostKeyValidationError.changedHostKey(
                    host: host,
                    port: port,
                    expected: existing.fingerprint,
                    presented: presentedKey.fingerprint
                )
            }

            existing.lastSeenAt = Date()
            entries[key] = existing
            saveAll(entries)
            return .matchedStoredHost(existing)
        }

        guard allowTrustOnFirstUse else {
            throw TermBridgeKitSSHHostKeyValidationError.unknownHost(
                host: host,
                port: port,
                fingerprint: presentedKey.fingerprint
            )
        }

        let entry = Entry(
            host: host,
            port: port,
            algorithm: presentedKey.algorithm,
            fingerprint: presentedKey.fingerprint,
            openSSHPublicKey: presentedKey.openSSHPublicKey,
            addedAt: Date(),
            lastSeenAt: Date()
        )
        entries[key] = entry
        saveAll(entries)
        return .trustedNewHost(entry)
    }

    private func hostKey(host: String, port: Int) -> String {
        "\(normalizeHost(host)):\(port)"
    }

    private func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func loadAll() -> [String: Entry] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func saveAll(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            assertionFailure("Failed to encode the SSH known-hosts store.")
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }

    static func normalizeFingerprint(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if trimmed.uppercased().hasPrefix("SHA256:") {
            return "SHA256:" + String(trimmed.dropFirst("SHA256:".count))
        }

        return "SHA256:\(trimmed)"
    }
}
