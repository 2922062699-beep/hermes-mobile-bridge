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

## Phase 1 Scope

Implemented:

- `GET /health`
- `GET /health/detailed`
- `POST /v1/mobile/pair`
- `GET /v1/mobile/capabilities`
- `POST /v1/mobile/doctor`
- `POST /v1/mobile/fix`

Not implemented yet:

- `/v1/runs` passthrough;
- SSE passthrough;
- approval passthrough;
- token usage aggregation;
- active Hermes Agent adaptation and automated fix actions.

## Security Boundary

The mobile app cannot send arbitrary commands to the PC. Future fix actions must be hardcoded allow-list actions.

See [docs/security.md](docs/security.md).
