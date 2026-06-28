#!/usr/bin/env bash
# Copy a locally built GhosttyKit.xcframework into Termini's expected location.
# Usage:
#   scripts/install-ghosttykit.sh /path/to/GhosttyKit.xcframework
# or set GHOSTTYKIT_PATH=/path/to/GhosttyKit.xcframework

set -euo pipefail

XCFRAMEWORK_PATH="${1:-${GHOSTTYKIT_PATH:-}}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${REPO_ROOT}/vendor/ghostty/macos"
METADATA_PATH="${REPO_ROOT}/vendor/ghosttykit-metadata.json"

find_git_root() {
  local dir="$1"
  while [[ "${dir}" != "/" ]]; do
    if [[ -d "${dir}/.git" || -f "${dir}/.git" ]]; then
      printf '%s\n' "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  return 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_metadata() {
  local source_dir="$1"
  local installed_at
  installed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local source_commit=""
  local source_branch=""
  local source_remote=""
  local source_dirty="false"

  if [[ -n "${source_dir}" ]] && git -C "${source_dir}" rev-parse --show-toplevel >/dev/null 2>&1; then
    source_commit="$(git -C "${source_dir}" rev-parse HEAD)"
    source_branch="$(git -C "${source_dir}" rev-parse --abbrev-ref HEAD)"
    source_remote="$(git -C "${source_dir}" config --get remote.origin.url || true)"
    if [[ -n "$(git -C "${source_dir}" status --porcelain)" ]]; then
      source_dirty="true"
    fi
  fi

  mkdir -p "$(dirname "${METADATA_PATH}")"
  cat > "${METADATA_PATH}" <<EOF
{
  "installed_at_utc": "$(json_escape "${installed_at}")",
  "xcframework_path": "$(json_escape "${DEST_DIR}/GhosttyKit.xcframework")",
  "source_git_root": "$(json_escape "${source_dir}")",
  "source_commit": "$(json_escape "${source_commit}")",
  "source_branch": "$(json_escape "${source_branch}")",
  "source_remote": "$(json_escape "${source_remote}")",
  "source_dirty": ${source_dirty}
}
EOF
}

if [[ -z "${XCFRAMEWORK_PATH}" ]]; then
  echo "error: provide the path to GhosttyKit.xcframework as an argument or via GHOSTTYKIT_PATH" >&2
  exit 1
fi

if [[ ! -d "${XCFRAMEWORK_PATH}" ]]; then
  echo "error: '${XCFRAMEWORK_PATH}' does not exist or is not a directory" >&2
  exit 1
fi

normalize_swiftpm_library_names() {
  local xcframework_dir="$1"

  local macos_dir="${xcframework_dir}/macos-arm64_x86_64"
  if [[ -f "${macos_dir}/ghostty-internal.a" ]]; then
    mv "${macos_dir}/ghostty-internal.a" "${macos_dir}/libghostty.a"
  fi

  for slice in ios-arm64 ios-arm64-simulator; do
    local ios_dir="${xcframework_dir}/${slice}"
    if [[ -f "${ios_dir}/libghostty-internal-fat.a" ]]; then
      mv "${ios_dir}/libghostty-internal-fat.a" "${ios_dir}/libghostty-fat.a"
    fi
  done

  /usr/bin/sed -i '' \
    -e 's/ghostty-internal\.a/libghostty.a/g' \
    -e 's/libghostty-internal-fat\.a/libghostty-fat.a/g' \
    "${xcframework_dir}/Info.plist"
}

mkdir -p "${DEST_DIR}"
rsync -a --delete "${XCFRAMEWORK_PATH%/}/" "${DEST_DIR}/GhosttyKit.xcframework/"
normalize_swiftpm_library_names "${DEST_DIR}/GhosttyKit.xcframework"
SOURCE_GIT_ROOT="$(find_git_root "$(cd "$(dirname "${XCFRAMEWORK_PATH}")" && pwd)" || true)"
write_metadata "${SOURCE_GIT_ROOT}"

echo "Installed GhosttyKit.xcframework to ${DEST_DIR}"
if [[ -n "${SOURCE_GIT_ROOT}" ]]; then
  echo "Recorded Ghostty metadata in ${METADATA_PATH}"
fi
