# TermBridgeKit

Drop a native terminal surface into a SwiftUI app. Uses Ghostty today,
but the SwiftUI API is kept small so the backend can change later.

## Requirements
- macOS 14+
- iOS 17+
- Swift 5.9 / Xcode 15+

When you consume `TermBridgeKit` through Swift Package Manager, the package
downloads `GhosttyKit` from this repo's GitHub Releases automatically.

If you're working on `TermBridgeKit` itself, you can still override that with a
local build at `vendor/ghostty/macos/GhosttyKit.xcframework`.

## Local GhosttyKit override
If you want to build or test against a local Ghostty checkout while working on
this package, build `GhosttyKit.xcframework` from the Ghostty project, then
copy it in:

```sh
# After building GhosttyKit.xcframework from Ghostty's embed instructions
./scripts/install-ghosttykit.sh /path/to/GhosttyKit.xcframework
```

The script copies the framework into `vendor/ghostty/macos`, which takes
priority over the GitHub release artifact during local package development.

If you keep a local Ghostty checkout in `vendor/ghostty`, you can rebuild and reinstall in one step:

```sh
./scripts/build-ghosttykit.sh
```

To update against a specific Ghostty ref first:

```sh
./scripts/build-ghosttykit.sh --fetch --ref <tag-or-commit>
```

Both scripts write `vendor/ghosttykit-metadata.json` so you can see exactly which Ghostty checkout and commit produced the installed framework.

To package the installed framework for a SwiftPM release artifact:

```sh
./scripts/package-ghosttykit-release.sh
```

## Architecture

```
TermBridgeKitTerminalView          SwiftUI view — wraps the Ghostty surface
TermBridgeKitTerminalController    Bridge between the view and your transport layer
TermBridgeKitTerminalAppearance    Theme + font sizing model for terminal presentation
TermBridgeKitSSHWorkspace          @Observable state machine — manages a full SSH session lifecycle
TermBridgeKitSSHSession            Low-level NIOSSH client wired to the controller
TermBridgeKitConnectionConfig      Validated SSH connection form model
TermBridgeKitConnectionGuide       Structured in-app setup guide content
```

## Quickstart — SSH workspace (recommended)

`TermBridgeKitSSHWorkspace` is the primary integration point. It owns the
controller, the session, and all connection state.

```swift
import SwiftUI
import TermBridgeKit

struct ContentView: View {
    @State private var workspace = TermBridgeKitSSHWorkspace(
        connection: .init(startupCommand: "tmux new -A -s myapp")
    )

    var body: some View {
        VStack {
            TermBridgeKitTerminalView(controller: workspace.controller)

            Button(workspace.isConnected ? "Disconnect" : "Connect") {
                Task { await workspace.toggleConnection() }
            }
            .disabled(!workspace.isConnected && !workspace.canConnect)
        }
        .task {
            // Optionally preload from environment variables and auto-connect
            if workspace.loadEnvironmentConfigurationIfAvailable() {
                await workspace.connect()
            }
        }
    }
}
```

### Configuring the connection

`TermBridgeKitConnectionConfig` is `@Observable`-friendly and validates itself:

```swift
workspace.connection.host     = "192.168.1.10"
workspace.connection.port     = 22
workspace.connection.username = "alice"

// Password auth
workspace.connection.authenticationMode = .password
workspace.connection.password = "secret"

// Private key auth (Ed25519, ECDSA P-256/P-384/P-521)
workspace.connection.authenticationMode = .privateKey
workspace.connection.privateKeyPEM = "-----BEGIN OPENSSH PRIVATE KEY-----\n..."

workspace.connection.term           = "xterm-256color"  // default
workspace.connection.startupCommand = "tmux new -A -s myapp"
workspace.connection.hostKeyPolicy  = .trustOnFirstUse
workspace.connection.hostKeyFingerprint = "SHA256:..."

workspace.connection.isReadyToConnect  // true when all required fields are set
workspace.connection.validationError   // human-readable error string or nil
```

### Workspace state

```swift
workspace.status        // TermBridgeKitSSHSession.Status — .disconnected / .connecting / .connected / .failed(String)
workspace.isConnected   // Bool
workspace.isConnecting  // Bool
workspace.canConnect    // Bool — not connecting AND connection is valid
workspace.statusMessage // Human-readable status string
workspace.terminalSize  // TermBridgeKitTerminalSize? — updated as the view resizes
workspace.diagnostics   // TermBridgeKitSurfaceDiagnostics?
```

## TermBridgeKitTerminalView

```swift
TermBridgeKitTerminalView(
    controller: workspace.controller,  // optional — pass nil for a standalone surface
    showsSystemKeyboard: true,         // iOS only — default true
    fontSize: 13                       // optional point size override
)
```

Or use the richer appearance model when you want a reusable theme/font profile:

```swift
let appearance = TermBridgeKitTerminalAppearance(
    theme: .midnightBloom,
    fontSize: 13
)

TermBridgeKitTerminalView(
    controller: workspace.controller,
    appearance: appearance
)
```

## Low-level usage — custom transport

Use `TermBridgeKitTerminalController` directly when you want to wire up your
own transport (WebSockets, local PTY, serial, etc.) instead of SSH.

```swift
@State private var controller = TermBridgeKitTerminalController()

// Wire output from your transport into the terminal
myTransport.onData = { data in
    controller.processRemoteOutput(data)
}

// Wire terminal input back to your transport
controller.onTransportWrite = { data in
    myTransport.write(data)
}

// React to terminal resize events
controller.onSizeChange = { size in
    myTransport.resize(cols: size.columns, rows: size.rows)
}
```

### Controller API

| Method / property | Description |
|---|---|
| `processRemoteOutput(_ data: Data)` | Feed bytes from remote → terminal. Buffers until the view attaches. |
| `focus()` / `blur()` | Forward focus events to the surface. |
| `currentSize() -> TermBridgeKitTerminalSize?` | Current terminal dimensions. |
| `visibleText() -> String?` | Snapshot of the visible screen text. |
| `diagnostics() -> TermBridgeKitSurfaceDiagnostics?` | Surface diagnostic info. |
| `onTransportWrite: ((Data) -> Void)?` | Called when the terminal wants to send bytes to the remote. |
| `onInputText: ((String) -> Void)?` | Called for printable text input (iOS soft keyboard path). |
| `onDeleteBackward: (() -> Void)?` | Called for backspace (iOS soft keyboard path). |
| `onSizeChange: ((TermBridgeKitTerminalSize) -> Void)?` | Called on every resize. |
| `onDiagnosticsChange: ((TermBridgeKitSurfaceDiagnostics) -> Void)?` | Called when diagnostics update. |

## SSH host verification

By default, `TermBridgeKit` uses trust-on-first-use host verification:

- The first successful connection stores the server's `SHA256:` host fingerprint.
- Later connections to the same `host:port` must present the same fingerprint.
- You can require a pre-trusted host with `.requireStoredHostKey`.
- You can pin an explicit fingerprint with `hostKeyFingerprint`.
- You can bypass checks with `.acceptAny`, but that should stay a local-debug-only escape hatch.

## SSH key support

| Type | Format |
|---|---|
| Ed25519 | OpenSSH PEM (`-----BEGIN OPENSSH PRIVATE KEY-----`) |
| ECDSA P-256 | SEC1 / PKCS#8 PEM |
| ECDSA P-384 | SEC1 / PKCS#8 PEM |
| ECDSA P-521 | SEC1 / PKCS#8 PEM |

Encrypted private keys are not supported.

## Environment variable preloading

`TermBridgeKitConnectionConfig.demoEnvironment()` (and
`workspace.loadEnvironmentConfigurationIfAvailable()`) reads:

| Variable | Required | Description |
|---|---|---|
| `TERMBRIDGEKIT_SSH_HOST` | yes | Hostname or IP |
| `TERMBRIDGEKIT_SSH_USER` | yes | SSH username |
| `TERMBRIDGEKIT_SSH_PRIVATE_KEY` | one of | PEM key (replace newlines with `\n`) |
| `TERMBRIDGEKIT_SSH_PASSWORD` | one of | Login password |
| `TERMBRIDGEKIT_SSH_PORT` | no | Default: `22` |
| `TERMBRIDGEKIT_SSH_NAME` | no | Display name for the connection |
| `TERMBRIDGEKIT_SSH_TERM` | no | Default: `xterm-256color` |
| `TERMBRIDGEKIT_SSH_COMMAND` | no | Default: `tmux new -A -s termbridgekit` |
| `TERMBRIDGEKIT_SSH_HOST_KEY_POLICY` | no | `trustOnFirstUse`, `requireStoredHostKey`, or `acceptAny` |
| `TERMBRIDGEKIT_SSH_HOST_KEY_FINGERPRINT` | no | Optional pinned `SHA256:` fingerprint |

Set these as scheme environment variables in Xcode (Edit Scheme → Run → Environment Variables).

## Debugging

Set `TERMBRIDGEKIT_DEBUG_INPUT=1` to log keyboard and mouse events.

## macOS demo

```sh
swift run TermBridgeKitDemo
```

## iOS demo

Generate and open the Xcode project with XcodeGen:

```sh
xcodegen generate
open TermBridgeKitDemos.xcodeproj
```

Select the `TermBridgeKitIOSDemo` scheme. Set `TERMBRIDGEKIT_SSH_*` environment
variables in the scheme to preload and auto-connect on launch.
