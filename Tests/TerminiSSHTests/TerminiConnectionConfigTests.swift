import Foundation
import XCTest
@testable import TerminiSSH

final class TerminiConnectionConfigTests: XCTestCase {
    func testExecRequestFlowsIntoResolvedSSHConfiguration() throws {
        let connection = TerminiConnectionConfig(
            host: "example.com",
            username: "tester",
            privateKeyPEM: "private-key",
            startupCommand: "tmux new -A -s scout",
            useExecRequest: true
        )

        let resolved = try XCTUnwrap(connection.resolvedSSHConfiguration())

        XCTAssertEqual(resolved.startupCommand, "tmux new -A -s scout")
        XCTAssertTrue(resolved.useExecRequest)
    }

    func testExecRequestRoundTripsThroughCodable() throws {
        let connection = TerminiConnectionConfig(useExecRequest: true)

        let data = try JSONEncoder().encode(connection)
        let decoded = try JSONDecoder().decode(TerminiConnectionConfig.self, from: data)

        XCTAssertTrue(decoded.useExecRequest)
    }

    func testOlderSerializedConnectionDefaultsToShellRequest() throws {
        let data = Data(#"{"name":"Legacy"}"#.utf8)

        let decoded = try JSONDecoder().decode(TerminiConnectionConfig.self, from: data)

        XCTAssertFalse(decoded.useExecRequest)
    }
}
