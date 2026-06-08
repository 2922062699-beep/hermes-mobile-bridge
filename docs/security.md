# Security Notes

Hermes Mobile Bridge runs on a user's PC and accepts requests from the mobile app on the local network. Keep the security boundary small.

## Rules

1. The mobile app must never send arbitrary PowerShell, shell, or agent commands.
2. `/v1/mobile/fix` must only run hardcoded allow-list actions.
3. Pairing codes are temporary and should expire or be invalidated after use.
4. API keys must not be committed to Git.
5. API keys should not be printed in full unless the user explicitly asks.
6. Bridge should default to LAN use, not public internet exposure.
7. Firewall changes must be explicit and user-approved.

## Phase 1

Phase 1 does not create firewall rules and does not expose public internet access.

The Bridge runs in the foreground. Closing the terminal stops the service.

Pairing codes expire after 5 minutes by default and are invalidated immediately after successful pairing.

Before pairing, `/health/detailed` only exposes public service identity and pairing metadata. Network details, Agent probe results, capabilities, doctor, fix actions, and passthrough endpoints require the paired mobile API key.

## Future Fix Actions

Allowed examples:

- regenerate mobile API key;
- regenerate pairing code;
- rerun diagnostics;
- refresh local IP detection;
- refresh model list;
- enable mobile safe-memory mode when supported.

Disallowed examples:

- run arbitrary shell command from mobile payload;
- edit unrelated Hermes Agent configuration;
- expose a public tunnel without explicit user action;
- print secrets in logs.
