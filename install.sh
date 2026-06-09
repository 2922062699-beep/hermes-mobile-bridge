#!/usr/bin/env bash
set -euo pipefail

COMMAND="start"
PORT="${HMB_PORT:-8642}"

if [ "${1:-}" != "" ]; then
  case "$1" in
    start|stop|doctor|status|qr)
      COMMAND="$1"
      shift
      ;;
  esac
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port|-p)
      if [ "${2:-}" = "" ]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

BRIDGE_PAYLOAD_REF="3e35ec6cca8cfecf3893cbf2c44f07647b663397"
JSDELIVR_BASE="https://cdn.jsdelivr.net/gh/2922062699-beep/hermes-mobile-bridge@${BRIDGE_PAYLOAD_REF}"
RAW_BASE="https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/${BRIDGE_PAYLOAD_REF}"
GHPROXY_BASE="https://ghproxy.com/${RAW_BASE}"
INSTALL_ROOT="${HMB_INSTALL_DIR:-${HOME}/.hermes-mobile-bridge}"
INSTALL_REQUEST_ID="$(node -e "console.log(Date.now())" 2>/dev/null || date +%s)"
FILES=(
  "package.json"
  "package-lock.json"
  "hermes-mobile.ps1"
  "hermes-mobile.sh"
  "bridge/server.mjs"
  "docs/protocol.md"
  "docs/release.md"
  "docs/security.md"
  "docs/troubleshooting.md"
  "README.md"
)

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required before installing Hermes Mobile Bridge dependencies." >&2
    echo "Install the LTS version from https://nodejs.org/en/download, then run this command again." >&2
    exit 1
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "npm was not found." >&2
    echo "Install Node.js LTS from https://nodejs.org/en/download, then run this command again." >&2
    exit 1
  fi
}

save_bridge_file() {
  local relative_path="$1"
  local target="${INSTALL_ROOT}/${relative_path}"
  local target_dir
  local source_names
  local source_urls
  local errors=()
  local index

  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"

  source_names=("jsDelivr" "GitHub raw" "ghproxy")
  source_urls=(
    "${JSDELIVR_BASE}/${relative_path}?v=${INSTALL_REQUEST_ID}"
    "${RAW_BASE}/${relative_path}?v=${INSTALL_REQUEST_ID}"
    "${GHPROXY_BASE}/${relative_path}?v=${INSTALL_REQUEST_ID}"
  )

  echo "Downloading ${relative_path}"
  for index in "${!source_urls[@]}"; do
    rm -f "$target"
    if curl -fsSL --max-time 30 "${source_urls[$index]}" -o "$target"; then
      if [ -f "$target" ]; then
        echo "  OK: ${source_names[$index]}"
        return
      fi
      errors+=("${source_names[$index]}: download finished but file is missing")
    else
      errors+=("${source_names[$index]}: curl failed")
    fi
  done

  echo "Failed to download ${relative_path} from all payload mirrors." >&2
  local error
  for error in "${errors[@]}"; do
    echo "  - ${error}" >&2
  done
  echo "Try again later, or manually git clone https://github.com/2922062699-beep/hermes-mobile-bridge and run the launcher locally." >&2
  exit 1
}

install_bridge_files() {
  mkdir -p "$INSTALL_ROOT"

  local file
  for file in "${FILES[@]}"; do
    save_bridge_file "$file"
  done
}

install_node_dependencies() {
  local package_lock="${INSTALL_ROOT}/package-lock.json"
  local npm_log="${INSTALL_ROOT}/npm-ci.log"

  if [ ! -f "$package_lock" ]; then
    echo "Cannot install Hermes Mobile Bridge dependencies because package-lock.json is missing from ${INSTALL_ROOT}." >&2
    exit 1
  fi

  echo "Installing Node dependencies with npm ci..."
  if ! (cd "$INSTALL_ROOT" && npm ci --omit=dev --no-audit --no-fund >"$npm_log" 2>&1); then
    echo "npm ci failed. Hermes Mobile Bridge will not start until dependencies install successfully." >&2
    cat "$npm_log" >&2
    exit 1
  fi
}

require_node
install_bridge_files
install_node_dependencies

LAUNCHER="${INSTALL_ROOT}/hermes-mobile.sh"
if [ ! -f "$LAUNCHER" ]; then
  echo "Cannot find installed launcher: ${LAUNCHER}" >&2
  exit 1
fi

chmod +x "$LAUNCHER"

echo "Hermes Mobile Bridge installed at ${INSTALL_ROOT}"
echo ""
"$LAUNCHER" "$COMMAND" --port "$PORT"
