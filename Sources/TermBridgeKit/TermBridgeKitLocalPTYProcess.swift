#if os(macOS)
import Darwin
import Dispatch
import Foundation

public struct TermBridgeKitProcessSpec: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectoryURL: URL

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectoryURL: URL
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectoryURL = workingDirectoryURL
    }
}

public final class TermBridgeKitLocalPTYProcess: @unchecked Sendable {
    public struct Size: Equatable, Sendable {
        public var columns: Int
        public var rows: Int

        public static let `default` = Size(columns: 120, rows: 34)

        public init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
        }
    }

    public enum PTYError: LocalizedError, Sendable {
        case unableToCreatePseudoTerminal(Int32)
        case unableToLaunch(String)

        public var errorDescription: String? {
            switch self {
            case .unableToCreatePseudoTerminal(let code):
                "Could not create a pseudo terminal. errno=\(code)"
            case .unableToLaunch(let message):
                message
            }
        }
    }

    public var onOutput: (@Sendable (Data) -> Void)?
    public var onExit: (@Sendable (Int32) -> Void)?

    private let queue = DispatchQueue(label: "dev.arach.TermBridgeKit.local-pty")
    private var masterFileDescriptor: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var lastRequestedSize: Size = .default

    public init() {}

    deinit {
        terminate()
    }

    public func start(
        spec: TermBridgeKitProcessSpec,
        initialSize: Size = .default
    ) throws {
        terminate()
        lastRequestedSize = initialSize

        var argv = CStringArray([spec.executableURL.path] + spec.arguments)
        var envp = CStringArray(Self.mergedEnvironment(extra: spec.environment))
        let workingDirectory = strdup(spec.workingDirectoryURL.path)
        let executablePath = strdup(spec.executableURL.path)

        defer {
            argv.deallocate()
            envp.deallocate()
            if let workingDirectory {
                free(workingDirectory)
            }
            if let executablePath {
                free(executablePath)
            }
        }

        var master: Int32 = -1
        var terminalSize = winsize(
            ws_row: Self.clampedTerminalValue(lastRequestedSize.rows),
            ws_col: Self.clampedTerminalValue(lastRequestedSize.columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let pid = forkpty(&master, nil, nil, &terminalSize)
        guard pid >= 0 else {
            throw PTYError.unableToCreatePseudoTerminal(errno)
        }

        if pid == 0 {
            if let workingDirectory, chdir(workingDirectory) != 0 {
                let reason = String(cString: strerror(errno))
                let path = String(cString: workingDirectory)
                Self.writeChildError("TermBridgeKit local PTY could not change into the working directory: \(path) (\(reason)).\r\n")
                _exit(1)
            }

            guard let executablePath else {
                Self.writeChildError("TermBridgeKit local PTY could not resolve the executable path.\r\n")
                _exit(1)
            }

            _ = argv.withUnsafeMutablePointer { argvPointer in
                envp.withUnsafeMutablePointer { envPointer in
                    execve(executablePath, argvPointer, envPointer)
                }
            }

            let message = "TermBridgeKit local PTY failed to launch \(spec.executableURL.lastPathComponent): \(String(cString: strerror(errno))).\r\n"
            Self.writeChildError(message)
            _exit(127)
        }

        masterFileDescriptor = master
        childPID = pid

        let flags = fcntl(master, F_GETFL)
        if flags >= 0 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }

        configureSources()
    }

    public func send(_ data: Data) {
        guard masterFileDescriptor >= 0, !data.isEmpty else { return }

        let payload = data
        queue.async { [weak self] in
            guard let self, self.masterFileDescriptor >= 0 else { return }
            payload.withUnsafeBytes { bytes in
                guard var cursor = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
                var remaining = bytes.count

                while remaining > 0 {
                    let written = Darwin.write(self.masterFileDescriptor, cursor, remaining)

                    if written > 0 {
                        remaining -= written
                        cursor = cursor.advanced(by: written)
                    } else if written == -1 && errno == EINTR {
                        continue
                    } else if written == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                        usleep(5_000)
                    } else {
                        break
                    }
                }
            }
        }
    }

    public func resize(to size: Size) {
        lastRequestedSize = size
        guard masterFileDescriptor >= 0 else { return }

        queue.async { [weak self] in
            guard let self, self.masterFileDescriptor >= 0 else { return }
            var terminalSize = winsize(
                ws_row: Self.clampedTerminalValue(self.lastRequestedSize.rows),
                ws_col: Self.clampedTerminalValue(self.lastRequestedSize.columns),
                ws_xpixel: 0,
                ws_ypixel: 0
            )
            _ = ioctl(self.masterFileDescriptor, TIOCSWINSZ, &terminalSize)
        }
    }

    public func terminate() {
        queue.sync {
            guard childPID > 0 else {
                cleanup()
                return
            }

            _ = kill(childPID, SIGTERM)
        }
    }

    private func configureSources() {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFileDescriptor, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.drainOutput()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self, self.masterFileDescriptor >= 0 else { return }
            close(self.masterFileDescriptor)
            self.masterFileDescriptor = -1
        }
        readSource.resume()
        self.readSource = readSource

        let processSource = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: queue)
        processSource.setEventHandler { [weak self] in
            self?.handleExit()
        }
        processSource.resume()
        self.processSource = processSource
    }

    private func drainOutput() {
        guard masterFileDescriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4_096)

        while true {
            let count = read(masterFileDescriptor, &buffer, buffer.count)

            if count > 0 {
                onOutput?(Data(buffer[0..<count]))
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            } else {
                break
            }
        }
    }

    private func handleExit() {
        var status: Int32 = 0
        let waitedPID = waitpid(childPID, &status, 0)

        let exitCode: Int32
        if waitedPID <= 0 {
            exitCode = 1
        } else if Self.didExit(status) {
            exitCode = Self.exitStatus(status)
        } else if Self.wasTerminatedBySignal(status) {
            exitCode = 128 + Self.terminationSignal(status)
        } else {
            exitCode = status
        }

        cleanup()
        onExit?(exitCode)
    }

    private func cleanup() {
        readSource?.cancel()
        readSource = nil

        processSource?.cancel()
        processSource = nil

        childPID = 0
    }

    private static func clampedTerminalValue(_ value: Int) -> UInt16 {
        UInt16(max(1, min(value, Int(UInt16.max))))
    }

    private static func didExit(_ status: Int32) -> Bool {
        (status & 0x7f) == 0
    }

    private static func exitStatus(_ status: Int32) -> Int32 {
        (status >> 8) & 0xff
    }

    private static func wasTerminatedBySignal(_ status: Int32) -> Bool {
        let signal = status & 0x7f
        return signal != 0 && signal != 0x7f
    }

    private static func terminationSignal(_ status: Int32) -> Int32 {
        status & 0x7f
    }

    private static func mergedEnvironment(extra: [String: String]) -> [String] {
        var environment = ProcessInfo.processInfo.environment
        let preferredPath = [
            "\(NSHomeDirectory())/.opencode/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")

        environment["PATH"] = preferredPath
        environment["NO_COLOR"] = nil
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["CLICOLOR"] = "1"
        environment["FORCE_COLOR"] = "1"
        environment["TERM_PROGRAM"] = "TermBridgeKit"

        for (key, value) in extra {
            environment[key] = value
        }

        return environment
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
    }

    private static func writeChildError(_ message: String) {
        message.withCString { buffer in
            _ = Darwin.write(STDERR_FILENO, buffer, strlen(buffer))
        }
    }
}

private struct CStringArray {
    private var storage: [UnsafeMutablePointer<CChar>?]

    init(_ strings: [String]) {
        storage = strings.map { strdup($0) } + [nil]
    }

    mutating func withUnsafeMutablePointer<R>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> R
    ) -> R {
        storage.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress)
        }
    }

    mutating func deallocate() {
        for pointer in storage where pointer != nil {
            free(pointer)
        }
        storage.removeAll(keepingCapacity: false)
    }
}
#endif
