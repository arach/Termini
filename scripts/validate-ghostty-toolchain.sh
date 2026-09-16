#!/usr/bin/env bash
# Build the pinned engine against an unmodified Xcode 26.3 SDK in a clean checkout.
# Does not install a framework or change the selected system developer directory.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$(cd "${1:?usage: $0 CLEAN_GHOSTTY_SOURCE EVIDENCE_DIR}" && pwd)"
mkdir -p "${2:?usage: $0 CLEAN_GHOSTTY_SOURCE EVIDENCE_DIR}"
EVIDENCE_DIR="$(cd "$2" && pwd)"
export SOURCE_DIR EVIDENCE_DIR REPO_ROOT
exec > >(tee "${EVIDENCE_DIR}/validation.log") 2>&1

[[ "$(uname -m)" == arm64 ]]
[[ "$(zig version)" == 0.15.2 ]]
[[ "$(command -v xcrun)" == /usr/bin/xcrun ]]
[[ -n "${DEVELOPER_DIR:-}" ]]
[[ "$(/usr/bin/xcodebuild -version)" == $'Xcode 26.3\nBuild version 17C529' ]]
[[ "$(git -C "${SOURCE_DIR}" rev-parse HEAD)" == 07d31666e73bce337b9cece60a884c67fe8906f4 ]]
[[ -z "$(git -C "${SOURCE_DIR}" status --porcelain)" ]]
[[ ! -d "${SOURCE_DIR}/.zig-cache" && ! -d "${SOURCE_DIR}/macos/GhosttyKit.xcframework" ]]
unset SDKROOT
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
case "${SDK_PATH}" in
  "${DEVELOPER_DIR}"/Platforms/MacOSX.platform/Developer/SDKs/*) ;;
  *) echo "Expected the selected Xcode's stock SDK, got ${SDK_PATH}"; exit 1 ;;
esac
export SDK_PATH
/usr/bin/xcodebuild -version
/usr/bin/xcrun --sdk macosx --show-sdk-version
/usr/bin/xcrun metal --version
zig version

# A fresh local cache ensures the build runner is linked with this toolchain.
export ZIG_LOCAL_CACHE_DIR="${SOURCE_DIR}/.zig-cache"
for patch in "${REPO_ROOT}"/patches/ghostty/0.1.6/*.patch; do
  git -C "${SOURCE_DIR}" apply --check "${patch}"
  git -C "${SOURCE_DIR}" apply "${patch}"
done
(
  cd "${SOURCE_DIR}"
  zig build -j3 -Dapp-runtime=none -Demit-xcframework=true \
    -Demit-macos-app=false -Demit-exe=false -Doptimize=ReleaseFast \
    -Dxcframework-target=native
)

# Verify the two new C exports and package the exact bytes for local runtime checks.
FRAMEWORK="${SOURCE_DIR}/macos/GhosttyKit.xcframework"
LIBRARY="${FRAMEWORK}/macos-arm64/libghostty-internal-fat.a"
[[ "$(/usr/bin/lipo -archs "${LIBRARY}")" == arm64 ]]
/usr/bin/nm -gU "${LIBRARY}" > "${EVIDENCE_DIR}/symbols.txt"
for symbol in ghostty_surface_new_with_frame_export ghostty_surface_request_frame_export; do
  grep -q " T _${symbol}$" "${EVIDENCE_DIR}/symbols.txt"
done
/usr/bin/tar -czf "${EVIDENCE_DIR}/GhosttyKit.xcframework.tar.gz" -C "${SOURCE_DIR}/macos" GhosttyKit.xcframework
python3 - <<'PY'
import hashlib, json, os, pathlib, subprocess
root = pathlib.Path(os.environ['REPO_ROOT'])
source = pathlib.Path(os.environ['SOURCE_DIR'])
evidence = pathlib.Path(os.environ['EVIDENCE_DIR'])
framework = source / 'macos/GhosttyKit.xcframework'
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def output(*args):
    return subprocess.check_output(args, text=True).strip()
result = {
    'status': 'PASS',
    'scope': 'Clean native arm64 engine build and exported symbols; runtime validation is separate',
    'sourceCommit': output('git', '-C', str(source), 'rev-parse', 'HEAD'),
    'consumerCommit': os.environ.get('GITHUB_SHA'),
    'runURL': 'https://github.com/' + os.environ.get('GITHUB_REPOSITORY', '') + '/actions/runs/' + os.environ.get('GITHUB_RUN_ID', ''),
    'xcode': output('/usr/bin/xcodebuild', '-version'),
    'sdkPath': os.environ['SDK_PATH'],
    'sdkVersion': output('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'),
    'sdkLibSystemSHA256': sha(pathlib.Path(os.environ['SDK_PATH']) / 'usr/lib/libSystem.tbd'),
    'zig': output('zig', 'version'),
    'metal': output('/usr/bin/xcrun', 'metal', '--version'),
    'sdkOverlay': False,
    'patches': [{'name': p.name, 'sha256': sha(p)} for p in sorted((root / 'patches/ghostty/0.1.6').glob('*.patch'))],
    'librarySHA256': sha(framework / 'macos-arm64/libghostty-internal-fat.a'),
    'archiveSHA256': sha(evidence / 'GhosttyKit.xcframework.tar.gz'),
}
(evidence / 'provenance.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
PY
