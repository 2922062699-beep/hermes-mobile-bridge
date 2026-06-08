# Hermes Mobile Bridge Protocol

Version: `0.1`

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

Pairing fields:

```json
{
  "pairing": {
    "available": true,
    "codeLength": 6,
    "expiresAt": "2026-06-08T10:30:00.000Z",
    "expiresInSeconds": 295,
    "used": false
  }
}
```

## Capabilities

```http
GET /v1/mobile/capabilities
Authorization: Bearer hm_xxxxx
```

Response:

```json
{
  "serverName": "Rick-PC",
  "version": "0.1.0",
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
  "action": "memory"
}
```

Phase 1 only accepts hardcoded allow-list actions and does not execute arbitrary PC commands.

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
      "key": "memory",
      "status": "unavailable",
      "detail": "Memory diagnostics require Hermes Agent integration in a later phase."
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
