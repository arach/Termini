#!/usr/bin/env bash
# Verify that GhosttyKit can link universal iOS Simulator consumers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCFRAMEWORK_PATH="${1:-${REPO_ROOT}/vendor/ghostty/macos/GhosttyKit.xcframework}"

if [[ ! -d "${XCFRAMEWORK_PATH}" ]]; then
  echo "error: '${XCFRAMEWORK_PATH}' does not exist or is not a directory" >&2
  exit 1
fi

SIMULATOR_DIR="$(find "${XCFRAMEWORK_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'ios-*-simulator' -print -quit)"
if [[ -z "${SIMULATOR_DIR}" ]]; then
  echo "error: GhosttyKit has no iOS Simulator slice" >&2
  exit 1
fi

SIMULATOR_LIBRARY="${SIMULATOR_DIR}/libghostty-fat.a"
if [[ ! -f "${SIMULATOR_LIBRARY}" ]]; then
  echo "error: iOS Simulator slice is missing normalized library ${SIMULATOR_LIBRARY}" >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "${SIMULATOR_LIBRARY}")"
for required in arm64 x86_64; do
  if [[ " ${ARCHITECTURES} " != *" ${required} "* ]]; then
    echo "error: iOS Simulator slice is missing ${required} (found: ${ARCHITECTURES})" >&2
    exit 1
  fi
done

echo "GhosttyKit iOS Simulator architectures: ${ARCHITECTURES}"
