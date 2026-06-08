# Hermes Mobile Bridge

Hermes Mobile Bridge is a small PC-side adapter for Hermes Mobile.

Its first job is simple:

- start a local mobile gateway;
- generate a temporary 6-digit pairing code;
- generate a mobile API key;
- let Hermes Mobile pair with `Gateway URL + Pairing Code`;
- expose basic capability status to the mobile connection diagnostic page.

It does not require Hermes Agent official changes for Phase 1.

## Quick Start

Run this in Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.ps1 | iex
```

Or, from this repository:

```powershell
.\hermes-mobile.ps1 start
```

The terminal prints:

```text
Node.js: v22.21.0
Install dir: C:\Users\you\AppData\Local\HermesMobileBridge
Gateway URL: http://192.168.31.191:8642

Hermes Mobile Bridge is running.

Gateway URL: http://192.168.31.191:8642
Pairing Code: 482913
Pairing Expires: 300 seconds
```

Open HermesMobile and enter:

- `Gateway URL`
- `Pairing Code`

HermesMobile exchanges the code for an API key through:

```text
POST /v1/mobile/pair
```

## Commands

After remote install, the files are stored in:

```text
%LOCALAPPDATA%\HermesMobileBridge
```

Run local commands from that folder:

```powershell
.\hermes-mobile.ps1 start
.\hermes-mobile.ps1 doctor
.\hermes-mobile.ps1 status
```

`start` runs the Bridge in the foreground. Keep the terminal open.

If port `8642` is busy, the launcher tries the next available port up to `8662` and prints the final Gateway URL.

Pairing codes expire after 5 minutes and are invalidated after successful pairing. Restart the Bridge to generate a new code.

If the phone cannot connect, run:

```powershell
.\hermes-mobile.ps1 status
```

The status output includes:

- capability status;
- detailed checks for Bridge, Hermes Agent, LLM models, and token usage;
- setup hints such as `HMB_AGENT_API_KEY` or `HMB_AGENT_URL`;
- phone URL, LAN IP, local health URL, and Windows Firewall hint.

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Hermes Agent Probe

Bridge probes the local Hermes Agent without changing its configuration.

Default probe target:

```text
http://127.0.0.1:8642
```

Override it with:

```powershell
$env:HMB_AGENT_URL = "http://127.0.0.1:8642"
```

If the Hermes Agent model endpoint requires an API key, set:

```powershell
$env:HMB_AGENT_API_KEY = "..."
```

Without `HMB_AGENT_API_KEY`, Bridge can still report whether Hermes Agent `/health` is reachable. It reports LLM/model probing as `warning` when `/v1/models` requires auth.

Use local diagnostics after Bridge is running:

```powershell
.\hermes-mobile.ps1 status
```

`status` and `doctor` call the loopback-only `GET /v1/local/status` endpoint. This exposes PC-side details to the terminal without making them public on the LAN.

## Product Boundary

Bridge is not the default chat gateway.

Default chat traffic stays on the existing direct path:

```text
Hermes Mobile -> Hermes Agent Gateway
```

Bridge is for setup, pairing, diagnostics, troubleshooting, and limited read-only helper passthrough. It should not take over runs, SSE, stop, or approval unless a future product decision explicitly changes this boundary.

After mobile pairing, Bridge also exposes:

```text
GET /v1/models
GET /v1/usage/summary
```

These endpoints forward read-only requests to the local Hermes Agent. The mobile `hm_` API key is only used to authorize access to Bridge; it is never forwarded to Hermes Agent. If Hermes Agent requires auth, set `HMB_AGENT_API_KEY` on the PC before starting Bridge.

## Phase 1 Scope

Implemented:

- `GET /health`
- `GET /health/detailed`
- `POST /v1/mobile/pair`
- `GET /v1/mobile/capabilities`
- `POST /v1/mobile/doctor`
- `POST /v1/mobile/fix`
- `GET /v1/models` passthrough
- `GET /v1/usage/summary` passthrough
- local Hermes Agent `/health` probe
- local Hermes Agent `/v1/models` probe when `HMB_AGENT_API_KEY` is available
- local Hermes Agent `/v1/usage/summary` probe when available

Not implemented yet:

- `/v1/runs` passthrough, intentionally out of scope for now;
- SSE passthrough, intentionally out of scope for now;
- stop passthrough, intentionally out of scope for now;
- approval passthrough, intentionally out of scope for now;
- token usage aggregation fallback;
- active Hermes Agent adaptation and automated fix actions.

## Security Boundary

The mobile app cannot send arbitrary commands to the PC. Future fix actions must be hardcoded allow-list actions.

See [docs/security.md](docs/security.md).

Release process notes: [docs/release.md](docs/release.md).
