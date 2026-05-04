# Termini

Drop a native terminal surface into a SwiftUI app. Uses Ghostty today,
but the SwiftUI API is kept small so the backend can change later.

> Termini evolved from `TermBridgeKit`; the rename happened at 0.1.0. The
> bundled `GhosttyKit.xcframework` is still hosted on the legacy
> `arach/TermBridgeKit` GitHub releases.

## Requirements
- macOS 14+
- iOS 17+
- Swift 5.9 / Xcode 15+

When you consume `Termini` through Swift Package Manager, the package
downloads `GhosttyKit` from this repo's GitHub Releases automatically.

If you're working on `Termini` itself, you can still override that with a
local build at `vendor/ghostty/macos/GhosttyKit.xcframework`.

## Products and transports

Termini now ships two SwiftPM library products:

| App shape | Products to depend on | Transport |
|---|---|---|
| iOS apps | `Termini` + `TerminiSSH` | SSH only; iOS sandboxing blocks local `fork`/PTY use. |
| macOS apps, local shell | `Termini` only | Local PTY via `TerminiLocalPTYWorkspace` / `TerminiLocalPTYProcess`. |
| macOS apps, remote shell | `Termini` + `TerminiSSH` | SSH via `TerminiSSHWorkspace`. |

`Termini` contains the renderer, terminal controller, appearance model, and
macOS-only local PTY transport. It depends on `GhosttyKit` only. `TerminiSSH`
contains the SSH connection models, host-key handling, SSH session, and SSH
workspace; it is the only product that pulls in SwiftNIO / NIOSSH and related
crypto packages.

### Migration note for 0.2.0

Hudson and Talkie drove this split so macOS-direct consumers can ship the
renderer plus local shell support without carrying unused SSH dependencies.

- Existing SSH integrations should add the `TerminiSSH` product and import it next to `Termini`:

```swift
import Termini
import TerminiSSH
```

- macOS local-shell integrations can depend on `Termini` only:

```swift
import Termini

@State private var workspace = TerminiLocalPTYWorkspace()
```

No renderer or SSH type was removed; the SSH surface moved into the new product.

## Local GhosttyKit override

If you want to build or test against a local Ghostty checkout while working on
this package, build `GhosttyKit.xcframework` from the Ghostty project, then
copy it in:

```sh
./scripts/install-ghosttykit.sh /path/to/GhosttyKit.xcframework
```

If you keep a local Ghostty checkout in `vendor/ghostty`, you can rebuild and reinstall in one step:

```sh
./scripts/build-ghosttykit.sh
```

To update against a specific Ghostty ref first:

```sh
./scripts/build-ghosttykit.sh --fetch --ref <tag-or-commit>
```

To package the installed framework for a SwiftPM release artifact:

```sh
./scripts/package-ghosttykit-release.sh
```

## Architecture

```
TerminiTerminalView           SwiftUI view — wraps the Ghostty surface
TerminiTerminalController     Bridge between the view and your transport layer
TerminiTerminalAppearance     Theme + font sizing model for terminal presentation
TerminiLocalPTYWorkspace      macOS @Observable state machine for local shell lifecycle
TerminiLocalPTYProcess        macOS forkpty-backed process transport
TerminiSSHWorkspace           @Observable state machine for SSH lifecycle (TerminiSSH)
TerminiSSHSession             Low-level NIOSSH client wired to the controller (TerminiSSH)
TerminiConnectionConfig       Validated SSH connection form model (TerminiSSH)
```

## Quickstart — macOS local PTY

```swift
import SwiftUI
import Termini

struct ContentView: View {
    @State private var workspace = TerminiLocalPTYWorkspace()

    var body: some View {
        TerminiTerminalView(controller: workspace.controller)
            .task { workspace.start() }
            .onDisappear { workspace.stop() }
    }
}
```

To launch a specific process:

```swift
let spec = TerminiProcessSpec(
    executableURL: URL(fileURLWithPath: "/bin/zsh"),
    arguments: ["-l"],
    environment: [:],
    workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory())
)

@State private var workspace = TerminiLocalPTYWorkspace(processSpec: spec)
```

## Quickstart — SSH workspace

```swift
import SwiftUI
import Termini
import TerminiSSH

struct ContentView: View {
    @State private var workspace = TerminiSSHWorkspace(
        connection: .init(startupCommand: "tmux new -A -s myapp")
    )

    var body: some View {
        VStack {
            TerminiTerminalView(controller: workspace.controller)

            Button(workspace.isConnected ? "Disconnect" : "Connect") {
                Task { await workspace.toggleConnection() }
            }
            .disabled(!workspace.isConnected && !workspace.canConnect)
        }
        .task {
            if workspace.loadEnvironmentConfigurationIfAvailable() {
                await workspace.connect()
            }
        }
    }
}
```

## TerminiTerminalView

```swift
TerminiTerminalView(
    controller: workspace.controller,
    showsSystemKeyboard: true,
    fontSize: 13
)
```

Or use the richer appearance model when you want a reusable theme/font profile:

```swift
let appearance = TerminiTerminalAppearance(
    theme: .midnightBloom,
    fontSize: 13,
    fontFamily: "SF Mono"
)

TerminiTerminalView(
    controller: workspace.controller,
    appearance: appearance
)
```

## Low-level usage — custom transport

Use `TerminiTerminalController` directly when you want to wire up your own
transport.

```swift
@State private var controller = TerminiTerminalController()

myTransport.onData = { data in
    controller.processRemoteOutput(data)
}

controller.onTransportWrite = { data in
    myTransport.write(data)
}

controller.onSizeChange = { size in
    myTransport.resize(cols: size.columns, rows: size.rows)
}
```

## SSH host verification

By default, `TerminiSSH` uses trust-on-first-use host verification:

- The first successful connection stores the server's `SHA256:` host fingerprint.
- Later connections to the same `host:port` must present the same fingerprint.
- You can require a pre-trusted host with `.requireStoredHostKey`.
- You can pin an explicit fingerprint with `hostKeyFingerprint`.
- You can bypass checks with `.acceptAny`, but that should stay a local-debug-only escape hatch.

Encrypted private keys are not supported.

## Environment variable preloading

`TerminiConnectionConfig.demoEnvironment()` and
`workspace.loadEnvironmentConfigurationIfAvailable()` read `TERMBRIDGEKIT_SSH_*`
variables for the SSH demos.

## Debugging

Set `TERMBRIDGEKIT_DEBUG_INPUT=1` to log keyboard and mouse events.

## macOS demo

```sh
swift run TerminiDemo
```

The macOS demo launches a local login shell through `TerminiLocalPTYWorkspace`.

## iOS demo

Generate and open the Xcode project with XcodeGen:

```sh
xcodegen generate
open TerminiDemos.xcodeproj
```

Select the `TerminiIOSDemo` scheme. Set `TERMBRIDGEKIT_SSH_*` environment
variables in the scheme to preload and auto-connect on launch.
