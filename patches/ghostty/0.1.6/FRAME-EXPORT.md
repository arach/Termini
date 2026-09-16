# Experimental macOS frame export

This source patch supports Hudson's isolated terminal proof. It adds no SwiftUI
code and preserves the layout of existing Ghostty configuration structs. It is
a private extension to pinned Ghostty source, not an upstream API. No published
binary pin changes in this branch.

## Ownership contract

`ghostty_surface_new_with_frame_export` creates an offscreen macOS surface with
an AppKit NSView as a platform anchor. No window is required. Pixel dimensions
come from the resize mailbox; local layer presentation is skipped, and rendering
uses event scheduling instead of a local display link.

The export callback runs after terminal render passes are encoded and before
their Metal command buffer is committed. Its texture and command buffer are
borrowed. Append a GPU copy into a host-owned bounded IOSurface pool. Never commit
or wait on the command buffer, modify the source, call surface APIs, wait for
external consumers, or access the source after GPU completion. Keep userdata
alive until `ghostty_surface_free` returns.

Engine target reuse waits for that same command buffer, including the export
copy. The host owns the destination's separate lease: publish after successful
producer completion and release after consumer GPU completion. The optional
`has_credit_cb` runs before GPU encoding: return false when the pool is full to
preserve dirty state and skip GPU frame work while parsing continues. The export
callback must still handle unavailable credit. On the engine app thread, call
`ghostty_surface_request_frame_export` when credit returns to schedule a current
frame even after output becomes idle. It performs no synchronous GPU wait.

This adds a GPU copy, avoids CPU frame serialization, and avoids holding engine
targets for an external process. Its latency/bandwidth cost needs a matched
benchmark before selecting a production export design.

## Build and test

Base source: `07d31666e73bce337b9cece60a884c67fe8906f4`. With a clean source checkout:

```sh
scripts/build-ghosttykit.sh --ghostty-dir /path/to/isolated/ghostty \
  --ref 07d31666e73bce337b9cece60a884c67fe8906f4 \
  --xcframework-target native
```

Subsequent builds omit `--ref`; the script refuses to switch dirty source.
`native` builds the current Mac architecture; the existing default is universal.
The simulator patch also repairs its final hunk count so plain `git apply` works.
All three patches were applied in order to a temporary index of the pinned source.

Zig 0.15.2 and Apple's Metal toolchain are required. This Zig linker has a known
failure with Xcode 26.4+ SDK libSystem stubs:
[Ghostty #11991](https://github.com/ghostty-org/ghostty/issues/11991),
[Zig #31658](https://codeberg.org/ziglang/zig/issues/31658).
Prefer a compatible Xcode/SDK selected per build via `DEVELOPER_DIR`.

The local 2026-09-16 proof used a private SDK overlay adding `arm64-macos` to
`arm64e-macos` target groups in the libSystem text stub. Local evidence records
the original stub hash and transformation. This enables a native diagnostic
build; it is **not release-toolchain qualification**. Installed SDKs are unchanged;
no modified SDK or generated binary is committed. The subsequent stock-toolchain
validation below supersedes that overlay build for native arm64 evidence.
Universal packaging and macOS/iOS release regressions remain open.

Hudson's `Tools/TerminalIsolationProbe/run.ts --terminal` uses the built native
XCFramework in an app-bundled XPC helper. It tests real PTY output/input, exported
glyph pixels, AppKit/Metal presentation, a stalled host main thread, frame-credit
saturation/recovery, and explicit PTY teardown.

The AppKit helper requires `XPCService.RunLoopType = NSRunLoop`. The default
`dispatch_main` can execute main-queue callbacks on a dispatch worker thread.
The fixture asserts AppKit initialization runs on the actual main thread.

Remaining product gates include input/IME/selection/accessibility, dynamic resize
pool generations, lifecycle recovery, peer signing, multiple panes, a second
consumer, and matched performance/soak tests. This does not enable Scout cutover.

## Validated compiler baseline — 2026-09-16

Use **Xcode 26.3 (17C529), its stock macOS 26.2 SDK, and Zig 0.15.2** for
this pinned engine. Xcode 27 is not a project requirement. A fresh arm64 GitHub
runner built the same source and patches without any SDK overlay:
[successful compiler validation](https://github.com/arach/Termini/actions/runs/35129139473).
Apple Metal reported version `32023.864`.

The workflow `.github/workflows/ghostty-toolchain.yml` invokes
`scripts/validate-ghostty-toolchain.sh` on a clean pinned checkout, verifies both
new C exports, and retains the native framework plus toolchain/source/patch hashes.
The Zig download has a fixed SHA-256. No engine build cache is restored.

The exact downloaded library was verified by SHA-256 before linking into Hudson's
local terminal helper. Its PTY/GPU fixture passed: 122 presentations, 8 completions
within the 300 ms host-main-stall sample, continued parsing with all three credits
held, immutable held frames, idle recovery, stale ACK rejection and PTY/helper
cleanup. These are correctness checks, not a throughput comparison with the
previous 121-frame run. The host fixture was compiled locally using the installed
CLT and macOS 26.5 SDK, targeting macOS 14; the engine was compiled by the pinned
Xcode 26.3 CI toolchain. This does not establish runtime compatibility on every
supported macOS release.

Native library SHA-256:
`8e8c285383241c6c62b6d256f2771e300f7ffa09410fbfa1e129eacc387a3cb2`.

This closes the stock compiler/SDK gate for **native macOS arm64 engine builds**.
Intel, universal/iOS builds, full product integration, release signing and the
wider OS/runtime regression matrix are not covered. No release binary pin changed.
