import Foundation
import NIOSSH
import XCTest
@testable import TermBridgeKitSSH

final class TermBridgeKitSSHKnownHostsTests: XCTestCase {
    private let ed25519PublicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJfkNV4OS33ImTXvorZr72q4v5XhVEQKfvqsxOEJ/XaR test@example"
    private let ecdsaPublicKey =
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIZS1APJofiPeoATC/VC4kKi7xRPdz934nSkFLTc0whYi3A8hEKHAOX9edgL1UWxRqRGQZq2wvvAIjAO9kCeiQA= test@example"

    func testEd25519FingerprintMatchesOpenSSH() throws {
        let knownKey = try makeKnownHostKey(from: ed25519PublicKey)

        XCTAssertEqual(knownKey.algorithm, "ssh-ed25519")
        XCTAssertEqual(knownKey.fingerprint, "SHA256:BFlAu0a4IRDePBZATpvzbeWrjzjd9h2/tKqd//EWd1Q")
    }

    func testTrustOnFirstUseStoresAndReusesHostFingerprint() throws {
        let store = makeStore()
        let key = try makeKnownHostKey(from: ed25519PublicKey)

        let firstResult = try store.validate(
            presentedKey: key,
            host: "example.com",
            port: 22,
            policy: .trustOnFirstUse,
            pinnedFingerprint: nil
        )
        let secondResult = try store.validate(
            presentedKey: key,
            host: "example.com",
            port: 22,
            policy: .trustOnFirstUse,
            pinnedFingerprint: nil
        )

        guard case .trustedNewHost(let trustedEntry) = firstResult else {
            return XCTFail("Expected TOFU to trust a new host on the first connection.")
        }
        guard case .matchedStoredHost(let matchedEntry) = secondResult else {
            return XCTFail("Expected TOFU to match the stored host on the second connection.")
        }

        XCTAssertEqual(trustedEntry.fingerprint, key.fingerprint)
        XCTAssertEqual(matchedEntry.fingerprint, key.fingerprint)
        XCTAssertEqual(store.entry(for: "example.com", port: 22)?.fingerprint, key.fingerprint)
    }

    func testRequireStoredHostKeyRejectsUnknownHosts() throws {
        let store = makeStore()
        let key = try makeKnownHostKey(from: ed25519PublicKey)

        XCTAssertThrowsError(
            try store.validate(
                presentedKey: key,
                host: "example.com",
                port: 22,
                policy: .requireStoredHostKey,
                pinnedFingerprint: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? TermBridgeKitSSHHostKeyValidationError,
                .unknownHost(
                    host: "example.com",
                    port: 22,
                    fingerprint: "SHA256:BFlAu0a4IRDePBZATpvzbeWrjzjd9h2/tKqd//EWd1Q"
                )
            )
        }
    }

    func testChangedHostKeyIsRejectedAfterTrustOnFirstUse() throws {
        let store = makeStore()
        let trustedKey = try makeKnownHostKey(from: ed25519PublicKey)
        let changedKey = try makeKnownHostKey(from: ecdsaPublicKey)

        _ = try store.validate(
            presentedKey: trustedKey,
            host: "example.com",
            port: 22,
            policy: .trustOnFirstUse,
            pinnedFingerprint: nil
        )

        XCTAssertThrowsError(
            try store.validate(
                presentedKey: changedKey,
                host: "example.com",
                port: 22,
                policy: .trustOnFirstUse,
                pinnedFingerprint: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? TermBridgeKitSSHHostKeyValidationError,
                .changedHostKey(
                    host: "example.com",
                    port: 22,
                    expected: trustedKey.fingerprint,
                    presented: changedKey.fingerprint
                )
            )
        }
    }

    func testPinnedFingerprintOverridesStoreLookup() throws {
        let store = makeStore()
        let key = try makeKnownHostKey(from: ed25519PublicKey)

        let result = try store.validate(
            presentedKey: key,
            host: "example.com",
            port: 22,
            policy: .requireStoredHostKey,
            pinnedFingerprint: "BFlAu0a4IRDePBZATpvzbeWrjzjd9h2/tKqd//EWd1Q"
        )

        XCTAssertEqual(result, .matchedPinnedFingerprint(key.fingerprint))
        XCTAssertNil(store.entry(for: "example.com", port: 22))
    }

    func testPinnedFingerprintRejectsUnexpectedHostKey() throws {
        let store = makeStore()
        let key = try makeKnownHostKey(from: ed25519PublicKey)

        XCTAssertThrowsError(
            try store.validate(
                presentedKey: key,
                host: "example.com",
                port: 22,
                policy: .acceptAny,
                pinnedFingerprint: "SHA256:5BPSYTUyN1Skyhu7TzjF8/t7ElACWtto8AhvcXV/2Ow"
            )
        ) { error in
            XCTAssertEqual(
                error as? TermBridgeKitSSHHostKeyValidationError,
                .fingerprintMismatch(
                    expected: "SHA256:5BPSYTUyN1Skyhu7TzjF8/t7ElACWtto8AhvcXV/2Ow",
                    presented: key.fingerprint
                )
            )
        }
    }

    private func makeKnownHostKey(from openSSHPublicKey: String) throws -> TermBridgeKitKnownHostKey {
        try TermBridgeKitKnownHostKey(hostKey: NIOSSHPublicKey(openSSHPublicKey: openSSHPublicKey))
    }

    private func makeStore() -> TermBridgeKitSSHKnownHostsStore {
        let suiteName = "TermBridgeKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TermBridgeKitSSHKnownHostsStore(
            userDefaults: defaults,
            storageKey: "known-hosts"
        )
    }
}
