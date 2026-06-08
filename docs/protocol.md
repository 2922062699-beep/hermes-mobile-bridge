# Hermes Mobile Bridge Protocol

Version: `0.2`

## Product Boundary

Bridge is a PC setup and diagnostics assistant, not the default chat gateway.

Default chat traffic remains:

```text
Hermes Mobile -> Hermes Agent Gateway
```

Bridge does not currently implement or plan to implement these chat gateway endpoints:

- `POST /v1/runs`
- `GET /v1/runs/{id}/events`
- `POST /v1/runs/{id}/stop`
- `POST /v1/runs/{id}/approval`

Bridge endpoints in this document are for pairing, diagnostics, troubleshooting, and limited read-only helper passthrough.

## Authentication

Before pairing, only these endpoints are public:

- `GET /health`
- `GET /health/detailed`
- `POST /v1/mobile/pair`

After pairing, HermesMobile stores the returned API key and sends:

```http
Authorization: Bearer hm_xxxxx
```

## Pairing

```http
POST /v1/mobile/pair
Content-Type: application/json
```

Request:

```json
{
  "pairingCode": "482913"
}
```

Response:

```json
{
  "apiKey": "hm_xxxxx",
  "serverName": "Rick-PC",
  "gatewayUrl": "http://192.168.31.191:8642",
  "capabilities": {
    "bridge": "ok",
    "agent": "unavailable",
    "runs": "unavailable",
    "sse": "unavailable",
    "llm": "unavailable",
    "memory": "unavailable",
    "usage": "unavailable",
    "approval": "unavailable",
    "stop": "unavailable",
    "files": "unavailable"
  }
}
```

Pairing code rules:

- 6 digits;
- generated on Bridge start;
- valid for 5 minutes by default;
- invalidated after successful pairing.
- if expired, restart Bridge to generate a new code.

Expired pairing response:

```json
{
  "error": "Pairing code has expired. Restart Bridge to get a new code."
}
```

HTTP status: `410 Gone`.

## Health Details

```http
GET /health/detailed
```

Before pairing, this endpoint returns only public service and pairing fields:

```json
{
  "status": "ok",
  "service": "hermes-mobile-bridge",
  "pairing": {
    "available": true,
    "codeLength": 6,
    "expiresAt": "2026-06-08T10:30:00.000Z",
    "expiresInSeconds": 295,
    "used": false
  }
}
```

After pairing, send:

```http
Authorization: Bearer hm_xxxxx
```

The authenticated response includes private diagnostics:

```json
{
  "network": {
    "lanIp": "192.168.31.191",
    "listenHost": "0.0.0.0",
    "localHealthUrl": "http://127.0.0.1:8642/health",
    "phoneUrl": "http://192.168.31.191:8642",
    "port": 8642
  },
  "pairing": {
    "available": true,
    "codeLength": 6,
    "expiresAt": "2026-06-08T10:30:00.000Z",
    "expiresInSeconds": 295,
    "used": false
  },
  "agent": {
    "agentUrl": "http://127.0.0.1:8642",
    "agentStatus": "ok",
    "agentDetail": "Hermes Agent is reachable at http://127.0.0.1:8642",
    "llmStatus": "warning",
    "llmDetail": "Model list requires Hermes Agent API key. Set HMB_AGENT_API_KEY to enable this probe.",
    "modelCount": 0
  }
}
```

## Local PC Status

```http
GET /v1/local/status
```

This endpoint is for `hermes-mobile.ps1 status` and `hermes-mobile.ps1 doctor`.

Rules:

- only available from loopback addresses on the PC;
- returns `403` from non-loopback clients;
- does not require the mobile pairing API key;
- returns the same private diagnostic shape as authenticated `/health/detailed`.

Agent probe rules:

- default target is `http://127.0.0.1:8642`;
- set `HMB_AGENT_URL` to override the target;
- Bridge probes `/health` without modifying Agent config;
- Bridge probes `/v1/models` only as a read operation;
- set `HMB_AGENT_API_KEY` if the Agent model endpoint requires auth;
- if the target is Hermes Mobile Bridge itself, it is ignored as an Agent candidate.

## Models Passthrough

```http
GET /v1/models
Authorization: Bearer hm_xxxxx
```

Bridge forwards this read-only request to:

```text
{HMB_AGENT_URL}/v1/models
```

Credential boundary:

- the mobile `hm_` API key authorizes access to Bridge only;
- Bridge never forwards the mobile API key to Hermes Agent;
- if Hermes Agent needs auth, Bridge uses `HMB_AGENT_API_KEY`;
- if `HMB_AGENT_API_KEY` is missing and Agent rejects `/v1/models`, Bridge returns `502` with a setup error.

Response:

```json
{
  "data": [
    {
      "id": "hermes-agent"
    }
  ]
}
```

## Token Usage Passthrough

```http
GET /v1/usage/summary
Authorization: Bearer hm_xxxxx
```

Bridge forwards this read-only request to:

```text
{HMB_AGENT_URL}/v1/usage/summary
```

Credential boundary:

- the mobile `hm_` API key authorizes access to Bridge only;
- Bridge never forwards the mobile API key to Hermes Agent;
- if Hermes Agent needs auth, Bridge uses `HMB_AGENT_API_KEY`;
- if Hermes Agent has no usage endpoint, Bridge returns `502` with a setup error.

Response shape is whatever Hermes Agent returns. Hermes Mobile currently expects a summary containing `today.totalTokens` or `today.total_tokens`.

## Capabilities

```http
GET /v1/mobile/capabilities
Authorization: Bearer hm_xxxxx
```

Response:

```json
{
  "serverName": "Rick-PC",
  "version": "0.2.0",
  "agent": {
    "agentUrl": "http://127.0.0.1:8642",
    "agentStatus": "ok",
    "llmStatus": "warning"
  },
  "capabilities": {
    "bridge": "ok",
    "agent": "ok",
    "llm": "warning",
    "usage": "unavailable"
  },
  "checks": [
    {
      "key": "bridge",
      "status": "ok",
      "label": "Bridge reachable",
      "detail": "Hermes Mobile Bridge is running"
    }
  ]
}
```

Status values:

- `ok`
- `warning`
- `failed`
- `unavailable`
- `checking`

## Doctor

```http
POST /v1/mobile/doctor
Authorization: Bearer hm_xxxxx
```

Phase 1 returns the same data as capabilities. Later phases will actively test Hermes Agent, LLM, memory, token usage, approval, SSE, and stop.

## Fix

```http
POST /v1/mobile/fix
Authorization: Bearer hm_xxxxx
Content-Type: application/json
```

Request:

```json
{
  "action": "usage"
}
```

Phase 1 only accepts hardcoded allow-list actions and does not execute arbitrary PC commands.

For `agent`, `llm`, and `usage`, the response reflects the latest Bridge probe result.

Allowed actions:

- `bridge`
- `agent`
- `runs`
- `sse`
- `llm`
- `memory`
- `usage`
- `approval`
- `stop`
- `files`
- `doctor`

Response:

```json
{
  "status": "completed",
  "healthStatus": "ok",
  "actions": [
    {
      "key": "usage",
      "status": "warning",
      "detail": "Token usage endpoint requires Hermes Agent API key. Set HMB_AGENT_API_KEY to enable this probe."
    }
  ],
  "capabilities": {
    "bridge": "ok",
    "agent": "unavailable"
  },
  "checks": [
    {
      "key": "bridge",
      "status": "ok",
      "label": "Bridge reachable",
      "detail": "Hermes Mobile Bridge is running"
    }
  ]
}
```
