# Troubleshooting

Use this checklist when Hermes Mobile cannot pair with the PC Bridge.

## Install Command Fails

Run:

```powershell
irm https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.ps1 | iex
```

If it fails while downloading files:

- confirm this PC can open GitHub raw URLs;
- retry from a normal PowerShell window;
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
- the phone and PC are on the same Wi-Fi or VPN;
- the mobile app uses the printed `Gateway URL`, not `127.0.0.1`;
- Windows Firewall allows Node.js on private networks;
- the PC is not on a guest Wi-Fi network that blocks device-to-device access.

Run:

```powershell
.\hermes-mobile.ps1 status
```

The output shows the local health URL, phone URL, LAN IP, and firewall hint.

## Status / Doctor Output

Run:

```powershell
.\hermes-mobile.ps1 status
```

or:

```powershell
.\hermes-mobile.ps1 doctor
```

The report includes:

- `Capabilities`: high-level module status exposed to Hermes Mobile;
- `Checks`: detailed Bridge, Hermes Agent, LLM, and token usage probe results;
- `Next steps`: concrete setup hints derived from failed or warning checks;
- `Network`: phone URL, local health URL, LAN IP, and firewall hint.

`Next steps` can mention:

- `HMB_AGENT_URL` if Bridge cannot reach Hermes Agent at the default local URL;
- `HMB_AGENT_API_KEY` if Hermes Agent requires auth for `/v1/models` or `/v1/usage/summary`;
- token usage limitations if `/v1/usage/summary` is unavailable;
- the Phase 1 boundary that Bridge does not take over chat runs, SSE, stop, or approval.

Token usage warnings do not block chat. They only affect Dashboard usage display and diagnostics.

## Pairing Code Expired

Pairing codes expire after 5 minutes and are invalidated after successful pairing.

Restart the Bridge to get a new code:

```powershell
.\hermes-mobile.ps1 start
```

## API Key Invalid

If Hermes Mobile was paired with an old Bridge process, restart Bridge and pair again with the new code.

The mobile API key is generated per Bridge process in Phase 1.

## Capabilities Are Unavailable

Phase 1 proves that Hermes Mobile can reach the Bridge and that the Bridge can diagnose selected PC-side modules.

These are expected to show `unavailable` in Phase 1 because Bridge intentionally does not take over chat traffic:

- Runs
- SSE
- Memory
- Approval
- Stop
- Files

Hermes Agent, LLM, and token usage can be `ok`, `warning`, or `unavailable` depending on whether the local Agent is reachable and whether `HMB_AGENT_API_KEY` is needed.
