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
- valid for the current Bridge process;
- invalidated after successful pairing.

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
