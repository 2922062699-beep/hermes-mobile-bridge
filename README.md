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

From this repository:

```powershell
.\hermes-mobile.ps1 start
```

The terminal prints:

```text
Hermes Mobile Bridge is running.

Gateway URL: http://192.168.31.191:8642
Pairing Code: 482913
```

Open HermesMobile and enter:

- `Gateway URL`
- `Pairing Code`

HermesMobile exchanges the code for an API key through:

```text
POST /v1/mobile/pair
```

## Commands

```powershell
.\hermes-mobile.ps1 start
.\hermes-mobile.ps1 doctor
.\hermes-mobile.ps1 status
```

`start` runs the Bridge in the foreground. Keep the terminal open.

## Phase 1 Scope

Implemented:

- `GET /health`
- `GET /health/detailed`
- `POST /v1/mobile/pair`
- `GET /v1/mobile/capabilities`
- `POST /v1/mobile/doctor`

Not implemented yet:

- `/v1/runs` passthrough;
- SSE passthrough;
- approval passthrough;
- token usage aggregation;
- automated fix actions.

## Security Boundary

The mobile app cannot send arbitrary commands to the PC. Future fix actions must be hardcoded allow-list actions.

See [docs/security.md](docs/security.md).
