import http from 'node:http'
import os from 'node:os'
import crypto from 'node:crypto'

const VERSION = '0.1.0'
const PORT = Number.parseInt(process.env.HMB_PORT || '8642', 10)
const PUBLIC_URL = process.env.HMB_PUBLIC_URL || `http://127.0.0.1:${PORT}`
const serverName = os.hostname()
let pairingCode = createPairingCode()
let pairingUsed = false
const mobileApiKey = `hm_${crypto.randomBytes(24).toString('hex')}`

function createPairingCode() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0')
}

function getCapabilities() {
  return {
    bridge: 'ok',
    agent: 'unavailable',
    runs: 'unavailable',
    sse: 'unavailable',
    llm: 'unavailable',
    memory: 'unavailable',
    usage: 'unavailable',
    approval: 'unavailable',
    stop: 'unavailable',
    files: 'unavailable',
  }
}

function getChecks() {
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
      status: 'unavailable',
      detail: 'Phase 1 has not connected to Hermes Agent yet',
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

function getDetailedStatus() {
  return {
    status: 'ok',
    version: VERSION,
    service: 'hermes-mobile-bridge',
    name: 'Hermes Mobile Bridge',
    platform: 'windows',
    serverName,
    gatewayUrl: PUBLIC_URL,
    pairing: {
      available: !pairingUsed,
      codeLength: 6,
    },
    capabilities: getCapabilities(),
    checks: getChecks(),
  }
}

async function handlePair(request, response) {
  const payload = await readJson(request)
  const receivedCode =
    typeof payload.pairingCode === 'string' ? payload.pairingCode.trim() : ''

  if (pairingUsed) {
    writeJson(response, 409, { error: 'Pairing code has already been used' })
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
    capabilities: getCapabilities(),
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
    writeJson(response, 200, getDetailedStatus())
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
      capabilities: getCapabilities(),
      checks: getChecks(),
    })
    return
  }

  if (request.method === 'POST' && url.pathname === '/v1/mobile/doctor') {
    writeJson(response, 200, getDetailedStatus())
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
  console.log('')
  console.log('Open HermesMobile:')
  console.log('1. Enter Gateway URL')
  console.log('2. Enter Pairing Code')
  console.log('')
  console.log('Keep this terminal open. Press Ctrl+C to stop.')
})
