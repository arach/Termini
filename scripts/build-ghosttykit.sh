#!/usr/bin/env bash
# Build GhosttyKit.xcframework from a local Ghostty checkout and install it
# into Termini's vendored path.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHOSTTY_DIR="${GHOSTTY_DIR:-${REPO_ROOT}/vendor/ghostty}"
GHOSTTY_REPO="${GHOSTTY_REPO:-https://github.com/ghostty-org/ghostty.git}"
GHOSTTY_REF="${GHOSTTY_REF:-}"
GHOSTTY_OPTIMIZE="${GHOSTTY_OPTIMIZE:-ReleaseFast}"
SHOULD_FETCH=0

usage() {
  cat <<EOF
Usage: $0 [--ghostty-dir PATH] [--ref REF] [--fetch] [--optimize MODE]

Options:
  --ghostty-dir PATH   Ghostty checkout to build from. Default: ${GHOSTTY_DIR}
  --ref REF            Git ref to check out before building.
  --fetch              Fetch origin before checking out REF.
  --optimize MODE      Zig optimize mode. Default: ${GHOSTTY_OPTIMIZE}

Env:
  GHOSTTY_DIR
  GHOSTTY_REPO
  GHOSTTY_REF
  GHOSTTY_OPTIMIZE
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing dependency '$1'" >&2
    exit 1
  fi
}

ensure_checkout() {
  if [[ -d "${GHOSTTY_DIR}/.git" || -f "${GHOSTTY_DIR}/.git" ]]; then
    return
  fi

  mkdir -p "$(dirname "${GHOSTTY_DIR}")"
  git clone --filter=blob:none "${GHOSTTY_REPO}" "${GHOSTTY_DIR}"
}

update_checkout() {
  if [[ -z "${GHOSTTY_REF}" ]]; then
    return
  fi

  if [[ -n "$(git -C "${GHOSTTY_DIR}" status --porcelain)" ]]; then
    echo "error: ${GHOSTTY_DIR} has uncommitted changes; refusing to switch refs" >&2
    exit 1
  fi

  if [[ "${SHOULD_FETCH}" == "1" ]]; then
    git -C "${GHOSTTY_DIR}" fetch --tags origin
  fi

  git -C "${GHOSTTY_DIR}" checkout "${GHOSTTY_REF}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ghostty-dir)
      GHOSTTY_DIR="$2"
      shift 2
      ;;
    --ref)
      GHOSTTY_REF="$2"
      shift 2
      ;;
    --fetch)
      SHOULD_FETCH=1
      shift
      ;;
    --optimize)
      GHOSTTY_OPTIMIZE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd git
require_cmd zig

ensure_checkout
update_checkout

(
  cd "${GHOSTTY_DIR}"
  zig build \
    -Dapp-runtime=none \
    -Demit-xcframework=true \
    -Demit-macos-app=false \
    -Demit-exe=false \
    -Doptimize="${GHOSTTY_OPTIMIZE}" \
    -Dxcframework-target=universal
)

"${REPO_ROOT}/scripts/install-ghosttykit.sh" "${GHOSTTY_DIR}/macos/GhosttyKit.xcframework"

echo "Built GhosttyKit from $(git -C "${GHOSTTY_DIR}" rev-parse --short HEAD)"
