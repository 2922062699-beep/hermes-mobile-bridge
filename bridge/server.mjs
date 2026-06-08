import http from 'node:http'
import os from 'node:os'
import crypto from 'node:crypto'

const VERSION = '0.2.0'
const PORT = Number.parseInt(process.env.HMB_PORT || '8642', 10)
const PUBLIC_URL = process.env.HMB_PUBLIC_URL || `http://127.0.0.1:${PORT}`
const AGENT_URL = (process.env.HMB_AGENT_URL || 'http://127.0.0.1:8642').replace(/\/+$/, '')
const PAIRING_TTL_MS = Number.parseInt(
  process.env.HMB_PAIRING_TTL_MS || '300000',
  10
)
const serverName = os.hostname()
let pairingCode = createPairingCode()
let pairingCreatedAt = Date.now()
let pairingUsed = false
const mobileApiKey = `hm_${crypto.randomBytes(24).toString('hex')}`
let agentProbeCache = {
  expiresAt: 0,
  result: null,
}

function getLanIp() {
  const interfaces = os.networkInterfaces()
  for (const entries of Object.values(interfaces)) {
    if (!entries) continue
    for (const entry of entries) {
      if (
        entry.family === 'IPv4' &&
        !entry.internal &&
        !entry.address.startsWith('169.254.')
      ) {
        return entry.address
      }
    }
  }

  return '127.0.0.1'
}

function createPairingCode() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0')
}

function getPairingExpiresAt() {
  return new Date(pairingCreatedAt + PAIRING_TTL_MS).toISOString()
}

function getPairingExpiresInSeconds() {
  return Math.max(0, Math.ceil((pairingCreatedAt + PAIRING_TTL_MS - Date.now()) / 1000))
}

function isPairingExpired() {
  return getPairingExpiresInSeconds() <= 0
}

function isPairingAvailable() {
  return !pairingUsed && !isPairingExpired()
}

function getIdentity(record) {
  return [
    typeof record.platform === 'string' ? record.platform : '',
    typeof record.service === 'string' ? record.service : '',
    typeof record.name === 'string' ? record.name : '',
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase()
}

async function fetchJson(url, timeoutMs = 1000, headers = {}) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(url, {
      headers,
      signal: controller.signal,
    })
    const text = await response.text()
    let data = undefined
    if (text.trim()) {
      try {
        data = JSON.parse(text)
      } catch {
        data = undefined
      }
    }

    return { response, data }
  } finally {
    clearTimeout(timeout)
  }
}

function parseModelList(value) {
  if (typeof value === 'string') return [value]
  if (Array.isArray(value)) return value.flatMap(parseModelList)
  if (!value || typeof value !== 'object') return []

  const ownModel =
    typeof value.model === 'string' ? value.model :
    typeof value.id === 'string' ? value.id :
    typeof value.name === 'string' ? value.name :
    typeof value.label === 'string' ? value.label :
    undefined
  const nested = ['data', 'models', 'available_models', 'availableModels', 'items']
    .flatMap((key) => parseModelList(value[key]))

  return ownModel ? [ownModel, ...nested] : nested
}

async function probeHermesAgent() {
  const now = Date.now()
  if (agentProbeCache.result && agentProbeCache.expiresAt > now) {
    return agentProbeCache.result
  }

  const result = {
    agentUrl: AGENT_URL,
    agentStatus: 'unavailable',
    agentDetail: `Hermes Agent was not reachable at ${AGENT_URL}`,
    llmStatus: 'unavailable',
    llmDetail: 'Model list was not checked because Hermes Agent is unavailable',
    modelCount: 0,
  }

  try {
    const health = await fetchJson(`${AGENT_URL}/health`, 1000)
    const record = health.data && typeof health.data === 'object' ? health.data : {}
    const status = typeof record.status === 'string' ? record.status.toLowerCase() : ''
    const identity = getIdentity(record)
    const isBridge = identity.includes('hermes-mobile-bridge')
    const isHermes = identity.includes('hermes')

    if (health.response.ok && status === 'ok' && isHermes && !isBridge) {
      result.agentStatus = 'ok'
      result.agentDetail = `Hermes Agent is reachable at ${AGENT_URL}`
    } else if (health.response.ok && isBridge) {
      result.agentDetail = `Skipped ${AGENT_URL} because it is Hermes Mobile Bridge, not Hermes Agent`
    } else {
      result.agentStatus = health.response.ok ? 'warning' : 'unavailable'
      result.agentDetail = `Agent health returned HTTP ${health.response.status}`
    }
  } catch {
    result.agentDetail = `Hermes Agent was not reachable at ${AGENT_URL}`
  }

  if (result.agentStatus === 'ok') {
    try {
      const headers = process.env.HMB_AGENT_API_KEY
        ? { Authorization: `Bearer ${process.env.HMB_AGENT_API_KEY}` }
        : {}
      const models = await fetchJson(`${AGENT_URL}/v1/models`, 1200, headers)
      const modelList = parseModelList(models.data)
      if (models.response.ok && modelList.length > 0) {
        result.llmStatus = 'ok'
        result.llmDetail = `${modelList.length} model(s) found`
        result.modelCount = modelList.length
      } else if (models.response.status === 401 || models.response.status === 403) {
        result.llmStatus = 'warning'
        result.llmDetail = 'Model list requires Hermes Agent API key. Set HMB_AGENT_API_KEY to enable this probe.'
      } else {
        result.llmStatus = 'warning'
        result.llmDetail = `Model list returned HTTP ${models.response.status}`
      }
    } catch {
      result.llmStatus = 'warning'
      result.llmDetail = 'Model list probe timed out or failed'
    }
  }

  agentProbeCache = {
    expiresAt: now + 5000,
    result,
  }
  return result
}

async function getCapabilities() {
  const probe = await probeHermesAgent()
  return {
    bridge: 'ok',
    agent: probe.agentStatus,
    runs: 'unavailable',
    sse: 'unavailable',
    llm: probe.llmStatus,
    memory: 'unavailable',
    usage: 'unavailable',
    approval: 'unavailable',
    stop: 'unavailable',
    files: 'unavailable',
  }
}

async function getChecks() {
  const probe = await probeHermesAgent()
  return [
    {
      key: 'bridge',
      label: 'Bridge reachable',
      status: 'ok',
      detail: 'Hermes Mobile Bridge is running',
    },
    {
      key: 'agent',
      label: 'Hermes Agent',
      status: probe.agentStatus,
      detail: probe.agentDetail,
    },
    {
      key: 'llm',
      label: 'LLM',
      status: probe.llmStatus,
      detail: probe.llmDetail,
    },
  ]
}

function writeJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
  })
  response.end(JSON.stringify(body, null, 2))
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = ''
    request.on('data', (chunk) => {
      body += chunk
      if (body.length > 1024 * 1024) {
        reject(new Error('Request body too large'))
        request.destroy()
      }
    })
    request.on('end', () => {
      if (!body.trim()) {
        resolve({})
        return
      }
      try {
        resolve(JSON.parse(body))
      } catch {
        reject(new Error('Invalid JSON body'))
      }
    })
    request.on('error', reject)
  })
}

function isAuthorized(request) {
  const header = request.headers.authorization || ''
  return header === `Bearer ${mobileApiKey}`
}

async function getDetailedStatus() {
  return {
    status: 'ok',
    version: VERSION,
    service: 'hermes-mobile-bridge',
    name: 'Hermes Mobile Bridge',
    platform: 'windows',
    serverName,
    gatewayUrl: PUBLIC_URL,
    network: {
      lanIp: getLanIp(),
      listenHost: '0.0.0.0',
      localHealthUrl: `http://127.0.0.1:${PORT}/health`,
      phoneUrl: PUBLIC_URL,
      port: PORT,
    },
    pairing: {
      available: isPairingAvailable(),
      codeLength: 6,
      expiresAt: getPairingExpiresAt(),
      expiresInSeconds: getPairingExpiresInSeconds(),
      used: pairingUsed,
    },
    agent: await probeHermesAgent(),
    capabilities: await getCapabilities(),
    checks: await getChecks(),
  }
}

function getAllowedFixAction(key) {
  const actions = {
    bridge: {
      key: 'bridge',
      status: 'ok',
      detail: 'Bridge is already running. Diagnostics refreshed.',
    },
    agent: {
      key: 'agent',
      status: 'unavailable',
      detail: 'Hermes Agent integration is not available in Bridge Phase 1.',
    },
    runs: {
      key: 'runs',
      status: 'unavailable',
      detail: 'Runs passthrough is not available in Bridge Phase 1.',
    },
    sse: {
      key: 'sse',
      status: 'unavailable',
      detail: 'SSE passthrough is not available in Bridge Phase 1.',
    },
    llm: {
      key: 'llm',
      status: 'unavailable',
      detail: 'LLM diagnostics require Hermes Agent integration in a later phase.',
    },
    memory: {
      key: 'memory',
      status: 'unavailable',
      detail: 'Memory diagnostics require Hermes Agent integration in a later phase.',
    },
    usage: {
      key: 'usage',
      status: 'unavailable',
      detail: 'Token usage diagnostics require Hermes Agent integration in a later phase.',
    },
    approval: {
      key: 'approval',
      status: 'unavailable',
      detail: 'Approval passthrough is not available in Bridge Phase 1.',
    },
    stop: {
      key: 'stop',
      status: 'unavailable',
      detail: 'Stop passthrough is not available in Bridge Phase 1.',
    },
    files: {
      key: 'files',
      status: 'unavailable',
      detail: 'File passthrough is not available in Bridge Phase 1.',
    },
    doctor: {
      key: 'doctor',
      status: 'ok',
      detail: 'Diagnostics refreshed.',
    },
  }

  return actions[key] || null
}

async function handleFix(request, response) {
  const payload = await readJson(request)
  const requestedAction =
    typeof payload.action === 'string' ? payload.action.trim() : 'doctor'
  const action = getAllowedFixAction(requestedAction)

  if (!action) {
    writeJson(response, 400, {
      error: 'Unsupported fix action',
      allowedActions: [
        'bridge',
        'agent',
        'runs',
        'sse',
        'llm',
        'memory',
        'usage',
        'approval',
        'stop',
        'files',
        'doctor',
      ],
    })
    return
  }

  const detailedStatus = await getDetailedStatus()
  writeJson(response, 200, {
    ...detailedStatus,
    status: 'completed',
    healthStatus: detailedStatus.status,
    actions: [action],
  })
}

async function handlePair(request, response) {
  const payload = await readJson(request)
  const receivedCode =
    typeof payload.pairingCode === 'string' ? payload.pairingCode.trim() : ''

  if (pairingUsed) {
    writeJson(response, 409, { error: 'Pairing code has already been used' })
    return
  }

  if (isPairingExpired()) {
    writeJson(response, 410, { error: 'Pairing code has expired. Restart Bridge to get a new code.' })
    return
  }

  if (receivedCode !== pairingCode) {
    writeJson(response, 401, { error: 'Invalid pairing code' })
    return
  }

  pairingUsed = true
  writeJson(response, 200, {
    apiKey: mobileApiKey,
    serverName,
    gatewayUrl: PUBLIC_URL,
    capabilities: await getCapabilities(),
  })
}

async function route(request, response) {
  const url = new URL(request.url || '/', `http://${request.headers.host}`)

  if (request.method === 'GET' && url.pathname === '/health') {
    writeJson(response, 200, {
      status: 'ok',
      version: VERSION,
      service: 'hermes-mobile-bridge',
      name: 'Hermes Mobile Bridge',
      platform: 'windows',
    })
    return
  }

  if (request.method === 'GET' && url.pathname === '/health/detailed') {
    writeJson(response, 200, await getDetailedStatus())
    return
  }

  if (request.method === 'POST' && url.pathname === '/v1/mobile/pair') {
    await handlePair(request, response)
    return
  }

  if (!isAuthorized(request)) {
    writeJson(response, 401, { error: 'Missing or invalid API key' })
    return
  }

  if (request.method === 'GET' && url.pathname === '/v1/mobile/capabilities') {
    writeJson(response, 200, {
      serverName,
      version: VERSION,
      gatewayUrl: PUBLIC_URL,
      agent: await probeHermesAgent(),
      capabilities: await getCapabilities(),
      checks: await getChecks(),
    })
    return
  }

  if (request.method === 'POST' && url.pathname === '/v1/mobile/doctor') {
    writeJson(response, 200, await getDetailedStatus())
    return
  }

  if (request.method === 'POST' && url.pathname === '/v1/mobile/fix') {
    await handleFix(request, response)
    return
  }

  writeJson(response, 404, { error: 'Not found' })
}

const server = http.createServer((request, response) => {
  route(request, response).catch((error) => {
    writeJson(response, 500, {
      error: error instanceof Error ? error.message : 'Internal server error',
    })
  })
})

server.listen(PORT, '0.0.0.0', () => {
  console.log('')
  console.log('Hermes Mobile Bridge is running.')
  console.log('')
  console.log(`Gateway URL: ${PUBLIC_URL}`)
  console.log(`Pairing Code: ${pairingCode}`)
  console.log(`Pairing Expires: ${getPairingExpiresInSeconds()} seconds`)
  console.log('')
  console.log('Open HermesMobile:')
  console.log('1. Enter Gateway URL')
  console.log('2. Enter Pairing Code')
  console.log('')
  console.log('Keep this terminal open. Press Ctrl+C to stop.')
})
