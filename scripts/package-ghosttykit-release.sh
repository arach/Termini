#!/usr/bin/env bash
# Package GhosttyKit.xcframework as a SwiftPM binary artifact zip and print its checksum.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCFRAMEWORK_PATH="${1:-${REPO_ROOT}/vendor/ghostty/macos/GhosttyKit.xcframework}"
OUTPUT_DIR="${2:-${REPO_ROOT}/dist}"
OUTPUT_PATH="${OUTPUT_DIR}/GhosttyKit.xcframework.zip"

if [[ ! -d "${XCFRAMEWORK_PATH}" ]]; then
  echo "error: '${XCFRAMEWORK_PATH}' does not exist or is not a directory" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_PATH}"

ditto -c -k --sequesterRsrc --keepParent "${XCFRAMEWORK_PATH}" "${OUTPUT_PATH}"

echo "Created ${OUTPUT_PATH}"
du -sh "${OUTPUT_PATH}"
echo "SwiftPM checksum:"
swift package compute-checksum "${OUTPUT_PATH}"
