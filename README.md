# TermBridgeKit

Drop a native terminal surface into a SwiftUI app. Uses Ghostty today,
but the SwiftUI API is kept small so the backend can change later.

## Requirements
- macOS 14+
- iOS 17+
- Swift 5.9 / Xcode 15+
- `vendor/ghostty/macos/GhosttyKit.xcframework` (git-ignored, must
  include the slices you want to ship)

## Get GhosttyKit
This repo does not ship Ghostty binaries. Build `GhosttyKit.xcframework` from the Ghostty project, then copy it in:

```sh
# After building GhosttyKit.xcframework from Ghostty's embed instructions
./scripts/install-ghosttykit.sh /path/to/GhosttyKit.xcframework
```

The script just copies the framework into `vendor/ghostty/macos`.

## Usage
Add TermBridgeKit via SPM or as a local checkout, then render the view:

```swift
import SwiftUI
import TermBridgeKit

struct TerminalPane: View {
    @State private var controller = TermBridgeKitTerminalController()

    var body: some View {
        TermBridgeKitTerminalView(controller: controller)
            .frame(minWidth: 600, minHeight: 400)
    }
}
```

Use `TermBridgeKitTerminalController` when you want to feed remote
terminal bytes into the surface, react to size changes, or forward input
to something like SSH.

Set `TERMBRIDGEKIT_DEBUG_INPUT=1` to log keyboard/mouse events.

## Demo
```sh
swift run TermBridgeKitDemo
```

## iOS demo
Generate and open the iOS demo project with XcodeGen:

```sh
xcodegen generate
open TermBridgeKitDemos.xcodeproj
```

The iOS demo expects SSH settings via scheme environment variables:

- `TERMBRIDGEKIT_SSH_HOST`
- `TERMBRIDGEKIT_SSH_USER`
- `TERMBRIDGEKIT_SSH_PRIVATE_KEY`
- `TERMBRIDGEKIT_SSH_PASSWORD` (optional)
- `TERMBRIDGEKIT_SSH_PORT` (optional)
- `TERMBRIDGEKIT_SSH_COMMAND` (optional)

For multiline private keys, replace newlines with `\n`.
