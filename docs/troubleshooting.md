# Troubleshooting

Use this checklist when Hermes Mobile cannot pair with the PC Bridge.

## Install Command Fails

Windows PowerShell:

Run:

```powershell
irm https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.ps1 | iex
```

macOS/Linux/WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.sh | bash
```

If it fails while downloading files:

- confirm this PC can open GitHub raw URLs;
- retry from a normal PowerShell window on Windows, or a normal Terminal window on macOS/Linux;
- check whether a company proxy or security tool blocks `raw.githubusercontent.com`.

## Node.js Missing

The Phase 1 Bridge runs with Node.js.

If the launcher prints `Node.js is required`, install Node.js and rerun the install command.

## Port Is Busy

The default port is `8642`.

If it is busy, the launcher tries the next available port up to `8662` and prints the final `Gateway URL`.

Always enter the printed `Gateway URL` in Hermes Mobile.

## Phone Cannot Connect

Check:

- the Bridge terminal is still open;
- the phone and computer are on the same Wi-Fi or VPN;
- the mobile app uses the printed `Gateway URL`, not `127.0.0.1`;
- Windows Firewall allows Node.js on private networks;
- on macOS, allow incoming network connections for Node.js if the system prompts on first launch;
- on Linux, confirm `ufw`, `firewalld`, or another firewall allows the printed TCP port;
- the computer is not on a guest Wi-Fi network that blocks device-to-device access.

Run:

Windows PowerShell:

```powershell
.\hermes-mobile.ps1 status
```

macOS/Linux/WSL:

```bash
./hermes-mobile.sh status
```

The output shows the local health URL, phone URL, LAN IP, and firewall hint.

## macOS First Launch Network Prompt

On first launch, macOS can ask whether Node.js may accept incoming network connections.

Allow Node.js on the local network. If you deny it, Hermes Mobile may not be able to reach the printed `Gateway URL` even though Bridge is running locally.

If the prompt does not appear and the phone cannot connect, check macOS firewall settings and rerun Bridge from Terminal.

## Linux Firewall Checks

If the phone cannot connect on Linux, confirm the printed Bridge port is open on the local network.

Common firewall managers include `ufw` and `firewalld`. Bridge does not change firewall rules automatically.

## Status / Doctor Output

Run:

Windows PowerShell:

```powershell
.\hermes-mobile.ps1 status
```

or:

```powershell
.\hermes-mobile.ps1 doctor
```

macOS/Linux/WSL:

```bash
./hermes-mobile.sh status
./hermes-mobile.sh doctor
```

The report includes:

- `Capabilities`: high-level module status exposed to Hermes Mobile;
- `Checks`: detailed Bridge, Hermes Agent, LLM, and token usage probe results;
- `Next steps`: concrete setup hints derived from failed or warning checks;
- `Network`: phone URL, local health URL, LAN IP, and firewall hint.

`Next steps` can mention:

- `HMB_AGENT_URL` if Bridge cannot reach Hermes Agent at the default local URL;
- `HMB_AGENT_API_KEY` if Hermes Agent requires auth for `/v1/models` or `/v1/usage/summary`;
- memory endpoint limitations if Hermes Agent does not expose a known read-only memory status endpoint;
- token usage limitations if `/v1/usage/summary` is unavailable;
- the Phase 1 boundary that Bridge does not take over chat runs, SSE, stop, or approval.

Token usage warnings do not block chat. They only affect Dashboard usage display and diagnostics.

## Memory Diagnostics

Bridge only probes Memory through read-only GET requests. It does not create, edit, delete, or sync memory records.

Default probe paths:

```text
/v1/memory/status,/memory/status,/v1/memory
```

If your Hermes Agent exposes a different read-only memory status endpoint, set it before starting Bridge:

Windows PowerShell:

```powershell
$env:HMB_MEMORY_STATUS_PATHS = "/v1/memory/status,/v1/memory"
.\hermes-mobile.ps1 start
```

macOS/Linux bash or zsh:

```bash
export HMB_MEMORY_STATUS_PATHS="/v1/memory/status,/v1/memory"
./hermes-mobile.sh start
```

If Memory remains `unavailable`, chat can still work. The warning means Bridge cannot currently confirm memory status from the PC Agent.

## Pairing Code Expired

Pairing codes expire after 5 minutes and are invalidated after successful pairing.

Restart the Bridge to get a new code:

Windows PowerShell:

```powershell
.\hermes-mobile.ps1 start
```

macOS/Linux/WSL:

```bash
./hermes-mobile.sh start
```

## API Key Invalid

If Hermes Mobile was paired with an old Bridge process, restart Bridge and pair again with the new code.

The mobile API key is generated per Bridge process in Phase 1.

## Pairing Requires HMB_AGENT_API_KEY

If Hermes Agent requires auth for `/v1/models`, Bridge needs `HMB_AGENT_API_KEY` before pairing. Otherwise Hermes Mobile could pair successfully but fail later when it tries to chat directly with Hermes Agent.

In an interactive terminal, `hermes-mobile.ps1 start` or `hermes-mobile.sh start` asks for the Agent API key automatically before starting Bridge.

You can also set it manually:

Windows PowerShell:

```powershell
$env:HMB_AGENT_API_KEY = "<Agent API Key>"
.\hermes-mobile.ps1 start
```

macOS/Linux bash or zsh:

```bash
export HMB_AGENT_API_KEY="<Agent API Key>"
./hermes-mobile.sh start
```

If you started Bridge through the remote install command, stop it, set `HMB_AGENT_API_KEY`, then run the install/start command again.

## Capabilities Are Unavailable

Phase 1 proves that Hermes Mobile can reach the Bridge and that the Bridge can diagnose selected PC-side modules.

These are expected to show `unavailable` in Phase 1 because Bridge intentionally does not take over chat traffic:

- Runs
- SSE
- Memory
- Approval
- Stop
- Files

Hermes Agent, LLM, Memory, and token usage can be `ok`, `warning`, or `unavailable` depending on whether the local Agent is reachable, which read-only endpoints it exposes, and whether `HMB_AGENT_API_KEY` is needed.
