#if os(macOS)
import Foundation
import Termini
import XCTest

final class TerminiLocalPTYProcessTests: XCTestCase {
    func testProcessCanBeReleasedFromExitCallback() throws {
        let owner = PTYProcessOwner()
        try owner.start()

        let deadline = Date().addingTimeInterval(2)
        while !owner.didReleaseProcess, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertTrue(owner.didReleaseProcess)
    }
}

private final class PTYProcessOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: TerminiLocalPTYProcess?
    private var releasedProcess = false

    var didReleaseProcess: Bool {
        lock.withLock { releasedProcess }
    }

    func start() throws {
        let process = TerminiLocalPTYProcess()
        process.onExit = { [weak self] _ in
            self?.releaseProcess()
        }
        lock.withLock {
            self.process = process
        }
        try process.start(
            spec: TerminiProcessSpec(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["0.05"],
                workingDirectoryURL: FileManager.default.temporaryDirectory
            )
        )
    }

    private func releaseProcess() {
        lock.withLock {
            process = nil
            releasedProcess = true
        }
    }
}
#endif
