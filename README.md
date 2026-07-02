# Termini

**Drop a native, GPU-accelerated terminal into your SwiftUI app — in about five lines.**

Termini wraps [Ghostty](https://ghostty.org)'s terminal engine in a small, SwiftUI-first
API. You get a real terminal surface (true colors, ligatures, Metal rendering) as an
ordinary `View`, plus ready-made state machines for the two things people actually do:
run a **local shell** (macOS) or connect over **SSH** (macOS + iOS).

The SwiftUI surface is kept deliberately small so the rendering backend can change later
without breaking your app.

```swift
import SwiftUI
import Termini

struct ContentView: View {
    @State private var workspace = TerminiLocalPTYWorkspace()   // a local login shell

    var body: some View {
        TerminiTerminalView(controller: workspace.controller)
            .task { workspace.start() }
            .onDisappear { workspace.stop() }
    }
}
```

That's a working terminal. The rest of this README shows how to install it, run the
demos, and go deeper.

---

## Contents

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Install](#install)
- [Try the demos](#try-the-demos-fastest-way-to-see-it-working)
- [Pick your products](#pick-your-products)
- [How the pieces fit](#how-the-pieces-fit)
- [Repo layout](#repo-layout)
- [Guides](#guides) — appearance, SSH, custom transports, host verification, debugging
- [Developing Termini itself](#developing-termini-itself)
- [Good to know](#good-to-know)
- [License](#license)

---

## What you get

- 🖥️ **A terminal as a SwiftUI `View`** — `TerminiTerminalView(controller:)`, drop it anywhere.
- 🐚 **Local shell on macOS** — `TerminiLocalPTYWorkspace` runs a `forkpty`-backed login shell.
- 🔌 **SSH on macOS + iOS** — `TerminiSSHWorkspace` over SwiftNIO/NIOSSH, with trust-on-first-use host keys.
- 🎨 **Themes & fonts** — `TerminiTerminalAppearance` for reusable color/font profiles.
- 🧩 **Bring-your-own transport** — wire `TerminiTerminalController` to any byte stream you like.
- 📦 **Zero manual setup** — SwiftPM downloads the prebuilt `GhosttyKit.xcframework` for you.

## Requirements

| | |
|---|---|
| macOS | 14+ |
| iOS | 17+ |
| Toolchain | Swift 5.9 / Xcode 15+ |

> iOS is **SSH-only**: the sandbox blocks local `fork`/PTY, so the local-shell APIs are macOS-only.

## Install

### Xcode

**File → Add Package Dependencies…** and enter:

```
https://github.com/arach/Termini.git
```

Then add the products you need to your target (see [Pick your products](#pick-your-products)).

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/arach/Termini.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Termini", package: "Termini"),
            // add only if you need SSH:
            .product(name: "TerminiSSH", package: "Termini"),
        ]
    )
]
```

On first build, SwiftPM downloads `GhosttyKit` from the project's GitHub Releases — no
manual framework wrangling. (Working on Termini itself? See
[Developing Termini itself](#developing-termini-itself) for the local-build override.)

## Try the demos (fastest way to see it working)

**macOS** — a local login shell in a window:

```sh
swift run TerminiDemo
```

**iOS** — generate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run the `TerminiIOSDemo` scheme:

```sh
xcodegen generate
open TerminiDemos.xcodeproj
```

For the iOS demo to auto-connect, set `TERMBRIDGEKIT_SSH_*` environment variables in the
scheme (see [Environment variables](#environment-variables)).

## Pick your products

Termini ships three SwiftPM products. Depend on the minimum your app shape needs:

| Your app | Depend on | Transport |
|---|---|---|
| **macOS, local shell** | `Termini` | Local PTY via `TerminiLocalPTYWorkspace` |
| **macOS, remote shell** | `Termini` + `TerminiSSH` | SSH via `TerminiSSHWorkspace` |
| **iOS** | `Termini` + `TerminiSSH` | SSH only (iOS blocks local PTY) |

`Termini` holds the renderer, controller, appearance model, and the macOS local-PTY
transport — it depends on `GhosttyKit` only. `TerminiSSH` is the **only** product that
pulls in SwiftNIO / NIOSSH, so macOS-direct apps stay lean by skipping it.

## How the pieces fit

```
TerminiTerminalView          SwiftUI view — wraps the Ghostty surface
TerminiTerminalController    Bridges the view to your transport layer
TerminiTerminalAppearance    Theme + font sizing model

 — in Termini (macOS local shell) —
TerminiLocalPTYWorkspace     @Observable lifecycle for a local shell
TerminiLocalPTYProcess       forkpty-backed process transport

 — in TerminiSSH —
TerminiSSHWorkspace          @Observable lifecycle for an SSH session
TerminiSSHSession            Low-level NIOSSH client wired to the controller
TerminiConnectionConfig      Validated SSH connection form model
```

The mental model: a **Workspace** owns a **Controller**, the `TerminiTerminalView`
renders that controller, and the controller talks to a **transport** (local PTY, SSH, or
your own). For most apps you only touch the Workspace and the View.

## Repo layout

```
Sources/
  Termini/        Renderer, controller, appearance, macOS local PTY
  TerminiSSH/     SSH session, host-key handling, SSH workspace
Examples/
  TerminiDemo/    macOS demo app (swift run TerminiDemo)
  TerminiIOSDemo/ iOS demo app (xcodegen + Xcode)
Tests/            XCTest suites for both products
scripts/          GhosttyKit build / install / packaging helpers
vendor/           Local GhosttyKit override drop point (gitignored framework)
patches/          Ghostty patches for the embedding APIs
project.yml       XcodeGen spec for the demo apps
Package.swift     Products, targets, and the GhosttyKit binary target
```

---

## Guides

### Customizing appearance

Pass quick overrides inline:

```swift
TerminiTerminalView(
    controller: workspace.controller,
    showsSystemKeyboard: true,
    fontSize: 13
)
```

…or build a reusable theme/font profile:

```swift
let appearance = TerminiTerminalAppearance(
    theme: .midnightBloom,
    fontSize: 13,
    fontFamily: "SF Mono"
)

TerminiTerminalView(controller: workspace.controller, appearance: appearance)
```

### Launching a specific local process (macOS)

```swift
let spec = TerminiProcessSpec(
    executableURL: URL(fileURLWithPath: "/bin/zsh"),
    arguments: ["-l"],
    environment: [:],
    workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory())
)

@State private var workspace = TerminiLocalPTYWorkspace(processSpec: spec)
```

### SSH workspace

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

### Custom transport

Use `TerminiTerminalController` directly to wire up any byte stream:

```swift
@State private var controller = TerminiTerminalController()

myTransport.onData = { data in
    controller.processRemoteOutput(data)      // bytes in  → screen
}

controller.onTransportWrite = { data in
    myTransport.write(data)                   // keystrokes → transport
}

controller.onSizeChange = { size in
    myTransport.resize(cols: size.columns, rows: size.rows)
}
```

### SSH host verification

`TerminiSSH` uses trust-on-first-use by default:

- The first successful connection stores the server's `SHA256:` fingerprint.
- Later connections to the same `host:port` must present the same fingerprint.
- Require a pre-trusted host with `.requireStoredHostKey`.
- Pin an explicit fingerprint with `hostKeyFingerprint`.
- Bypass checks with `.acceptAny` — keep this a local-debug-only escape hatch.

Encrypted private keys are not supported.

### Environment variables

| Variable | Effect |
|---|---|
| `TERMBRIDGEKIT_SSH_*` | Preloads SSH connection config (`TerminiConnectionConfig.demoEnvironment()` / `workspace.loadEnvironmentConfigurationIfAvailable()`). |
| `TERMBRIDGEKIT_DEBUG_INPUT=1` | Logs keyboard and mouse events. |

> The `TERMBRIDGEKIT_` prefix is retained from the project's previous name (see [Good to know](#good-to-know)).

---

## Developing Termini itself

Clone, then build and test like any SwiftPM package:

```sh
swift build
swift test
```

### Working against a local Ghostty build

By default the package downloads a released `GhosttyKit.xcframework`. To test against your
own Ghostty checkout, drop a framework into
`vendor/ghostty/macos/GhosttyKit.xcframework` and `Package.swift` will prefer it
automatically. The helper scripts do the work:

```sh
# Install a framework you built elsewhere:
./scripts/install-ghosttykit.sh /path/to/GhosttyKit.xcframework

# Or rebuild from a checkout in vendor/ghostty and install in one step:
./scripts/build-ghosttykit.sh

# Build against a specific Ghostty ref first:
./scripts/build-ghosttykit.sh --fetch --ref <tag-or-commit>

# Package the installed framework as a SwiftPM release artifact:
./scripts/package-ghosttykit-release.sh
```

---

## Good to know

- **Rename:** Termini evolved from `TermBridgeKit` (renamed at 0.1.0). The bundled
  `GhosttyKit.xcframework` is still hosted on the legacy `arach/TermBridgeKit` GitHub
  releases, and a few env-var names still carry the `TERMBRIDGEKIT_` prefix.
- **0.2.0 product split:** SSH moved into its own `TerminiSSH` product so macOS-direct apps
  can ship the renderer + local shell without carrying SwiftNIO/NIOSSH. No renderer or SSH
  type was removed — existing SSH integrations just add `import TerminiSSH` alongside
  `import Termini`.
- **Third-party code:** see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for bundled
  dependencies, including Ghostty.

---

## License

Termini is released under the [MIT License](LICENSE).

Termini stands on [Ghostty](https://ghostty.org) — the bundled `GhosttyKit.xcframework`
is Ghostty's terminal engine, © Mitchell Hashimoto and the Ghostty contributors, also
MIT-licensed. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the full notice.
</content>
</invoke>
