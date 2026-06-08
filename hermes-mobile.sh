#!/usr/bin/env bash
set -euo pipefail

COMMAND="start"
PORT="${HMB_PORT:-8642}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="${SCRIPT_DIR}/bridge/server.mjs"
PID_FILE="${SCRIPT_DIR}/hermes-mobile.pid"

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

test_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required for this Phase 1 bridge. Install Node.js, then retry." >&2
    exit 1
  fi

  node --version
}

get_platform() {
  local uname_value
  uname_value="$(uname -s 2>/dev/null || echo unknown)"
  case "$uname_value" in
    Darwin)
      echo "macos"
      ;;
    Linux)
      echo "linux"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "windows"
      ;;
    *)
      echo "$uname_value"
      ;;
  esac
}

get_primary_lan_ip() {
  node - <<'NODE'
const os = require('node:os');
const interfaces = os.networkInterfaces();
for (const entries of Object.values(interfaces)) {
  if (!entries) continue;
  for (const entry of entries) {
    if (
      entry.family === 'IPv4' &&
      !entry.internal &&
      !entry.address.startsWith('169.254.')
    ) {
      console.log(entry.address);
      process.exit(0);
    }
  }
}
console.log('127.0.0.1');
NODE
}

resolve_bridge_port() {
  local preferred_port="$1"
  node - "$preferred_port" <<'NODE'
const net = require('node:net');
const preferred = Number.parseInt(process.argv[2], 10);

function canListen(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once('error', () => resolve(false));
    server.once('listening', () => {
      server.close(() => resolve(true));
    });
    server.listen(port, '0.0.0.0');
  });
}

(async () => {
  for (let port = preferred; port <= preferred + 20; port += 1) {
    if (await canListen(port)) {
      console.log(port);
      return;
    }
  }

  console.error(`No available TCP port found from ${preferred} to ${preferred + 20}.`);
  process.exit(1);
})();
NODE
}

get_local_gateway_url() {
  local selected_port="$1"
  local ip
  ip="$(get_primary_lan_ip)"
  echo "http://${ip}:${selected_port}"
}

get_firewall_hint() {
  local selected_port="$1"
  case "$(get_platform)" in
    windows)
      echo "Bridge does not change firewall rules. If the phone cannot connect to TCP ${selected_port}, allow Node.js on private networks."
      ;;
    macos)
      echo "Bridge does not change firewall rules. If the phone cannot connect to TCP ${selected_port}, check macOS network permissions (System Settings -> Network -> Firewall) and allow Node.js if needed."
      ;;
    linux)
      echo "Bridge does not change firewall rules. If the phone cannot connect to TCP ${selected_port}, check firewall rules such as ufw or firewalld for this Linux distribution."
      ;;
    *)
      echo "Bridge does not change firewall rules. If the phone cannot connect to TCP ${selected_port}, check this computer's firewall or network security settings."
      ;;
  esac
}

write_network_help() {
  local gateway_url="$1"
  local selected_port="$2"

  echo ""
  echo "Network checks:"
  echo "  Local health: http://127.0.0.1:${selected_port}/health"
  echo "  Phone URL: ${gateway_url}"
  echo "  LAN IP: $(get_primary_lan_ip)"
  echo "  Firewall: $(get_firewall_hint "$selected_port")"
  echo ""
  echo "If the phone cannot connect:"
  echo "  1. Keep this terminal open."
  echo "  2. Confirm phone and computer are on the same Wi-Fi or VPN."
  case "$(get_platform)" in
    windows)
      echo "  3. Allow Node.js through Windows Firewall for private networks."
      ;;
    macos)
      echo "  3. Check macOS network permissions: System Settings -> Network -> Firewall."
      ;;
    linux)
      echo "  3. Check Linux firewall rules such as ufw or firewalld."
      ;;
    *)
      echo "  3. Check this computer's firewall or network security settings."
      ;;
  esac
}

get_agent_url() {
  local agent_url="${HMB_AGENT_URL:-http://127.0.0.1:8642}"
  echo "${agent_url%/}"
}

test_agent_models_endpoint() {
  local agent_url
  agent_url="$(get_agent_url)"
  HMB_PROBE_AGENT_URL="$agent_url" node - <<'NODE'
const agentUrl = process.env.HMB_PROBE_AGENT_URL;
const headers = {};
if (process.env.HMB_AGENT_API_KEY) {
  headers.Authorization = `Bearer ${process.env.HMB_AGENT_API_KEY}`;
}

const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 4000);

fetch(`${agentUrl}/v1/models`, { headers, signal: controller.signal })
  .then((response) => {
    clearTimeout(timeout);
    if (response.ok) {
      console.log('ok');
      return;
    }
    if (response.status === 401 || response.status === 403) {
      console.log('auth-required');
      return;
    }
    console.log('unknown');
  })
  .catch(() => {
    clearTimeout(timeout);
    console.log('unknown');
  });
NODE
}

ensure_agent_api_key_for_pairing() {
  if [ "${HMB_AGENT_API_KEY:-}" != "" ]; then
    export HMB_AGENT_API_KEY
    return
  fi

  local probe
  probe="$(test_agent_models_endpoint)"
  if [ "$probe" != "auth-required" ]; then
    return
  fi

  echo ""
  echo "Hermes Agent model endpoint requires an API key."
  echo "Bridge needs HMB_AGENT_API_KEY so Hermes Mobile can chat directly with Hermes Agent after pairing."

  if [[ ! -t 0 ]]; then
    echo "This terminal is not interactive. Export HMB_AGENT_API_KEY before starting Bridge, then retry pairing."
    return
  fi

  local plain_key
  read -r -s -p "Enter Hermes Agent API Key for this Bridge session, or press Enter to skip: " plain_key
  echo ""

  plain_key="${plain_key#"${plain_key%%[![:space:]]*}"}"
  plain_key="${plain_key%"${plain_key##*[![:space:]]}"}"
  if [ "$plain_key" = "" ]; then
    echo "Skipped HMB_AGENT_API_KEY. Pairing will fail if Hermes Agent requires auth."
    return
  fi

  export HMB_AGENT_API_KEY="$plain_key"
  echo "HMB_AGENT_API_KEY is set for this Bridge process."
}

fetch_local_status() {
  local selected_port="$1"
  HMB_STATUS_URL="http://127.0.0.1:${selected_port}/v1/local/status" node - <<'NODE'
const url = process.env.HMB_STATUS_URL;
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 5000);

fetch(url, { signal: controller.signal })
  .then(async (response) => {
    clearTimeout(timeout);
    const text = await response.text();
    if (!response.ok) {
      console.error(`HTTP ${response.status}: ${text}`);
      process.exit(1);
    }
    process.stdout.write(text);
  })
  .catch((error) => {
    clearTimeout(timeout);
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
NODE
}

write_status_report() {
  local status_json="$1"
  local selected_port="$2"
  STATUS_JSON="$status_json" HMB_FIREWALL_HINT="$(get_firewall_hint "$selected_port")" node - <<'NODE'
const result = JSON.parse(process.env.STATUS_JSON);
const firewallHint = process.env.HMB_FIREWALL_HINT;

function writeCapabilities(capabilities) {
  console.log('');
  console.log('Capabilities:');
  if (!capabilities || typeof capabilities !== 'object') {
    console.log('  unavailable');
    return;
  }
  for (const [key, value] of Object.entries(capabilities)) {
    console.log(`  ${key}: ${value}`);
  }
}

function writeChecks(checks) {
  console.log('');
  console.log('Checks:');
  if (!Array.isArray(checks) || checks.length === 0) {
    console.log('  unavailable');
    return;
  }
  for (const check of checks) {
    const label = check.label || check.key || 'unknown';
    const status = check.status || 'unknown';
    console.log(`  [${status}] ${label}`);
    if (check.detail) console.log(`    ${check.detail}`);
  }
}

function getSetupHints(result) {
  const details = [];
  if (result.agent) {
    for (const key of ['agentDetail', 'llmDetail', 'usageDetail']) {
      if (result.agent[key]) details.push(String(result.agent[key]));
    }
  }
  if (Array.isArray(result.checks)) {
    for (const check of result.checks) {
      if (check.detail) details.push(String(check.detail));
    }
  }

  const detailText = details.join(' ');
  const hints = [];
  if (detailText.includes('HMB_AGENT_API_KEY')) {
    hints.push('Set HMB_AGENT_API_KEY before starting Bridge if Hermes Agent requires auth for models or token usage.');
  }
  if (detailText.includes('not reachable')) {
    hints.push('Start Hermes Agent Gateway, or set HMB_AGENT_URL to the correct local Agent URL before starting Bridge.');
  }
  if ((result.capabilities && result.capabilities.usage !== 'ok') || detailText.includes('/v1/usage/summary')) {
    hints.push('Token usage is optional for chat. It only affects Dashboard usage display and diagnostics.');
  }
  if ((result.capabilities && result.capabilities.memory !== 'ok') || detailText.includes('memory status')) {
    hints.push('Memory diagnostics are read-only. If your Agent exposes a memory status endpoint, set HMB_MEMORY_STATUS_PATHS before starting Bridge.');
  }
  if (
    result.capabilities &&
    ['runs', 'sse', 'stop', 'approval'].some((key) => result.capabilities[key] === 'unavailable')
  ) {
    hints.push('Bridge intentionally does not take over chat traffic in Phase 1. Keep Hermes Mobile chat pointed at Hermes Agent Gateway.');
  }

  return [...new Set(hints)];
}

function writeSetupHints(result) {
  const hints = getSetupHints(result);
  if (hints.length === 0) return;
  console.log('');
  console.log('Next steps:');
  hints.forEach((hint, index) => {
    console.log(`  ${index + 1}. ${hint}`);
  });
}

console.log('Hermes Mobile Bridge status');
console.log('');
console.log(`Status: ${result.status}`);
console.log(`Version: ${result.version}`);
console.log(`Gateway URL: ${result.gatewayUrl}`);
if (result.pairing) {
  console.log(`Pairing available: ${result.pairing.available}`);
  if (result.pairing.expiresInSeconds !== undefined && result.pairing.expiresInSeconds !== null) {
    console.log(`Pairing expires in: ${result.pairing.expiresInSeconds}s`);
  }
}

writeCapabilities(result.capabilities);
writeChecks(result.checks);
writeSetupHints(result);

if (result.network) {
  console.log('');
  console.log('Network:');
  console.log(`  Local health: ${result.network.localHealthUrl}`);
  console.log(`  Phone URL: ${result.network.phoneUrl}`);
  console.log(`  LAN IP: ${result.network.lanIp}`);
  console.log(`  Listen host: ${result.network.listenHost}`);
  console.log(`  Firewall: ${firewallHint}`);
  console.log('');
  console.log('If the phone cannot connect, keep Bridge running and check same Wi-Fi/VPN plus this computer firewall or network permissions for Node.js.');
}
NODE
}

read_pairing_qr_payload() {
  local qr_payload="$1"
  QR_PAYLOAD="$qr_payload" node - <<'NODE'
try {
  const url = new URL(process.env.QR_PAYLOAD);
  if (url.protocol !== 'hmb:' || url.hostname !== 'pair') process.exit(1);
  if (url.searchParams.get('v') !== '1') process.exit(1);
  const bridgeUrl = url.searchParams.get('b');
  const code = url.searchParams.get('c');
  if (!bridgeUrl || !code) process.exit(1);
  console.log(JSON.stringify({ b: bridgeUrl, c: code }));
} catch {
  process.exit(1);
}
NODE
}

render_pairing_qr() {
  local qr_payload="$1"
  echo "Scan with Hermes Mobile:"
  if ! (cd "$SCRIPT_DIR" && QR_PAYLOAD="$qr_payload" node --input-type=module - <<'NODE')
const qrcode = (await import('qrcode-terminal')).default;
qrcode.generate(process.env.QR_PAYLOAD, { small: true });
NODE
  then
    echo "QR rendering unavailable. Pair manually with the Gateway URL and Pairing Code above."
  fi
  echo ""
}

start_bridge() {
  local node_version="$1"
  local selected_port
  local gateway_url

  selected_port="$(resolve_bridge_port "$PORT")"
  gateway_url="$(get_local_gateway_url "$selected_port")"

  if [ "$selected_port" != "$PORT" ]; then
    echo "Port ${PORT} is busy. Using port ${selected_port} instead."
  fi

  echo "Node.js: ${node_version}"
  echo "Install dir: ${SCRIPT_DIR}"
  echo "Gateway URL: ${gateway_url}"
  write_network_help "$gateway_url" "$selected_port"
  ensure_agent_api_key_for_pairing

  export HMB_PORT="$selected_port"
  export HMB_PUBLIC_URL="$gateway_url"
  export HMB_AGENT_URL="${HMB_AGENT_URL:-http://127.0.0.1:8642}"

  node "$SERVER" &
  local bridge_pid="$!"
  echo "$bridge_pid" > "$PID_FILE"

  cleanup() {
    rm -f "$PID_FILE"
    if kill -0 "$bridge_pid" >/dev/null 2>&1; then
      kill "$bridge_pid" >/dev/null 2>&1 || true
    fi
  }

  trap cleanup EXIT INT TERM
  wait "$bridge_pid"
}

stop_bridge() {
  if [ ! -f "$PID_FILE" ]; then
    echo "Hermes Mobile Bridge PID file was not found."
    echo "If Bridge is running in another terminal, press Ctrl+C in that terminal."
    return
  fi

  local bridge_pid
  bridge_pid="$(cat "$PID_FILE")"
  if [ "$bridge_pid" = "" ]; then
    rm -f "$PID_FILE"
    echo "Hermes Mobile Bridge PID file was empty."
    return
  fi

  if node - "$bridge_pid" <<'NODE'
const pid = Number.parseInt(process.argv[2], 10);
if (!Number.isFinite(pid)) process.exit(1);
try {
  process.kill(pid, 'SIGTERM');
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
NODE
  then
    rm -f "$PID_FILE"
    echo "Hermes Mobile Bridge stop signal sent to PID ${bridge_pid}."
  else
    rm -f "$PID_FILE"
    echo "Hermes Mobile Bridge was not reachable by PID ${bridge_pid}."
    exit 1
  fi
}

write_qr_report() {
  local status_json="$1"
  local pairing_json
  local qr_payload

  pairing_json="$(STATUS_JSON="$status_json" node - <<'NODE'
const result = JSON.parse(process.env.STATUS_JSON);
const pairing = result.pairing;
if (!pairing || !pairing.available) {
  console.error('unavailable');
  if (pairing && pairing.used) console.error('Pairing code has already been used.');
  else if (pairing && pairing.expiresInSeconds <= 0) console.error('Pairing code has expired.');
  process.exit(2);
}
if (!pairing.qrPayload) {
  console.error('Bridge did not return a QR payload. Update or restart Hermes Mobile Bridge, then retry.');
  process.exit(1);
}
console.log(JSON.stringify({
  expiresInSeconds: pairing.expiresInSeconds,
  qrPayload: pairing.qrPayload,
}));
NODE
  )" || {
    local status="$?"
    echo "Hermes Mobile Bridge pairing QR is not available."
    if [ "$status" -eq 2 ]; then
      STATUS_JSON="$status_json" node - <<'NODE'
const result = JSON.parse(process.env.STATUS_JSON);
const pairing = result.pairing;
if (pairing && pairing.used) console.log('Pairing code has already been used.');
else if (pairing && pairing.expiresInSeconds <= 0) console.log('Pairing code has expired.');
NODE
    fi
    echo "Restart Bridge with: ./hermes-mobile.sh start --port ${PORT}"
    exit 1
  }

  qr_payload="$(PAIRING_JSON="$pairing_json" node - <<'NODE'
const pairing = JSON.parse(process.env.PAIRING_JSON);
console.log(pairing.qrPayload);
NODE
  )"

  local payload_values
  if ! payload_values="$(read_pairing_qr_payload "$qr_payload")"; then
    echo "Bridge returned an invalid QR payload. Restart Hermes Mobile Bridge, then retry."
    exit 1
  fi

  echo "Hermes Mobile Bridge pairing QR"
  echo ""
  PAYLOAD_VALUES="$payload_values" node - <<'NODE'
const payload = JSON.parse(process.env.PAYLOAD_VALUES);
console.log(`Gateway URL: ${payload.b}`);
console.log(`Pairing Code: ${payload.c}`);
NODE
  PAIRING_JSON="$pairing_json" node - <<'NODE'
const pairing = JSON.parse(process.env.PAIRING_JSON);
if (pairing.expiresInSeconds !== undefined && pairing.expiresInSeconds !== null) {
  console.log(`Pairing expires in: ${pairing.expiresInSeconds}s`);
}
console.log(`QR Payload: ${pairing.qrPayload}`);
NODE
  echo ""
  render_pairing_qr "$qr_payload"
  echo "Or pair manually with the values above."
}

NODE_VERSION="$(test_node)"

case "$COMMAND" in
  start)
    if [ ! -f "$SERVER" ]; then
      echo "Cannot find Bridge server: ${SERVER}" >&2
      exit 1
    fi
    start_bridge "$NODE_VERSION"
    ;;
  stop)
    stop_bridge
    ;;
  doctor|status)
    STATUS_URL="http://127.0.0.1:${PORT}/v1/local/status"
    if ! STATUS_JSON="$(fetch_local_status "$PORT")"; then
      echo "Hermes Mobile Bridge is not reachable at ${STATUS_URL}"
      exit 1
    fi
    write_status_report "$STATUS_JSON" "$PORT"
    ;;
  qr)
    STATUS_URL="http://127.0.0.1:${PORT}/v1/local/status"
    if ! STATUS_JSON="$(fetch_local_status "$PORT")"; then
      echo "Hermes Mobile Bridge is not reachable at ${STATUS_URL}"
      exit 1
    fi
    write_qr_report "$STATUS_JSON"
    ;;
esac
