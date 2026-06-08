param(
  [ValidateSet("start", "doctor", "status", "qr")]
  [string]$Command = "start",
  [int]$Port = 8642
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Server = Join-Path $ScriptDir "bridge\server.mjs"

function Test-Node {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) {
    throw "Node.js is required for this Phase 1 bridge. Install Node.js, then retry."
  }

  return (& node --version)
}

function Test-TcpPortAvailable {
  param([int]$CandidatePort)

  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new(
      [System.Net.IPAddress]::Any,
      $CandidatePort
    )
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($listener) {
      $listener.Stop()
    }
  }
}

function Resolve-BridgePort {
  param([int]$PreferredPort)

  for ($candidate = $PreferredPort; $candidate -le ($PreferredPort + 20); $candidate++) {
    if (Test-TcpPortAvailable $candidate) {
      return $candidate
    }
  }

  throw "No available TCP port found from $PreferredPort to $($PreferredPort + 20)."
}

function Get-LocalGatewayUrl {
  param([int]$SelectedPort)

  $ip = Get-PrimaryLanIp

  return "http://$ip`:$SelectedPort"
}

function Get-PrimaryLanIp {
  $ip = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
      $_.IPAddress -notlike "127.*" -and
      $_.IPAddress -notlike "169.254.*" -and
      $_.PrefixOrigin -ne "WellKnown"
    } |
    Select-Object -First 1 -ExpandProperty IPAddress

  if (-not $ip) {
    $ip = "127.0.0.1"
  }

  return $ip
}

function Get-FirewallHint {
  param([int]$SelectedPort)

  return "Bridge does not change firewall rules. If the phone cannot connect to TCP $SelectedPort, allow Node.js on private networks."
}

function Write-NetworkHelp {
  param(
    [string]$GatewayUrl,
    [int]$SelectedPort
  )

  Write-Host ""
  Write-Host "Network checks:"
  Write-Host "  Local health: http://127.0.0.1:$SelectedPort/health"
  Write-Host "  Phone URL: $GatewayUrl"
  Write-Host "  LAN IP: $(Get-PrimaryLanIp)"
  Write-Host "  Firewall: $(Get-FirewallHint $SelectedPort)"
  Write-Host ""
  Write-Host "If the phone cannot connect:"
  Write-Host "  1. Keep this terminal open."
  Write-Host "  2. Confirm phone and PC are on the same Wi-Fi or VPN."
  Write-Host "  3. Allow Node.js through Windows Firewall for private networks."
}

function Get-AgentUrl {
  $agentUrl = $env:HMB_AGENT_URL
  if (-not $agentUrl) {
    $agentUrl = "http://127.0.0.1:8642"
  }

  return $agentUrl.TrimEnd("/")
}

function Get-HttpStatusCodeFromError {
  param($ErrorRecord)

  $response = $ErrorRecord.Exception.Response
  if ($response -and $response.StatusCode -ne $null) {
    return [int]$response.StatusCode
  }

  return $null
}

function Test-CanPrompt {
  if (-not [Environment]::UserInteractive) {
    return $false
  }

  if ($Host.Name -ne "ConsoleHost") {
    return $false
  }

  try {
    return -not [Console]::IsInputRedirected
  } catch {
    return $false
  }
}

function Convert-SecureStringToPlainText {
  param([Security.SecureString]$SecureValue)

  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Test-AgentModelsEndpoint {
  $agentUrl = Get-AgentUrl
  $headers = @{}
  if ($env:HMB_AGENT_API_KEY) {
    $headers.Authorization = "Bearer $($env:HMB_AGENT_API_KEY)"
  }

  try {
    Invoke-WebRequest -UseBasicParsing -Method GET -Uri "$agentUrl/v1/models" -Headers $headers -TimeoutSec 4 | Out-Null
    return "ok"
  } catch {
    $statusCode = Get-HttpStatusCodeFromError $_
    if ($statusCode -eq 401 -or $statusCode -eq 403) {
      return "auth-required"
    }

    return "unknown"
  }
}

function Ensure-AgentApiKeyForPairing {
  if ($env:HMB_AGENT_API_KEY) {
    return
  }

  $probe = Test-AgentModelsEndpoint
  if ($probe -ne "auth-required") {
    return
  }

  Write-Host ""
  Write-Host "Hermes Agent model endpoint requires an API key."
  Write-Host "Bridge needs HMB_AGENT_API_KEY so Hermes Mobile can chat directly with Hermes Agent after pairing."

  if (-not (Test-CanPrompt)) {
    Write-Host "This terminal is not interactive. Set HMB_AGENT_API_KEY before starting Bridge, then retry pairing."
    return
  }

  $secureKey = Read-Host "Enter Hermes Agent API Key for this Bridge session, or press Enter to skip" -AsSecureString
  if (-not $secureKey -or $secureKey.Length -eq 0) {
    Write-Host "Skipped HMB_AGENT_API_KEY. Pairing will fail if Hermes Agent requires auth."
    return
  }

  $plainKey = Convert-SecureStringToPlainText $secureKey
  if (-not $plainKey.Trim()) {
    Write-Host "Skipped HMB_AGENT_API_KEY. Pairing will fail if Hermes Agent requires auth."
    return
  }

  $env:HMB_AGENT_API_KEY = $plainKey.Trim()
  Write-Host "HMB_AGENT_API_KEY is set for this Bridge process."
}

function Write-BridgeCapabilities {
  param($Capabilities)

  Write-Host ""
  Write-Host "Capabilities:"
  if (-not $Capabilities) {
    Write-Host "  unavailable"
    return
  }

  $Capabilities.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value)"
  }
}

function Write-BridgeChecks {
  param($Checks)

  Write-Host ""
  Write-Host "Checks:"
  if (-not $Checks) {
    Write-Host "  unavailable"
    return
  }

  foreach ($check in @($Checks)) {
    $label = if ($check.label) { $check.label } else { $check.key }
    $status = if ($check.status) { $check.status } else { "unknown" }
    Write-Host "  [$status] $label"
    if ($check.detail) {
      Write-Host "    $($check.detail)"
    }
  }
}

function Get-BridgeSetupHints {
  param($Result)

  $hints = @()
  $details = @()

  if ($Result.agent) {
    if ($Result.agent.agentDetail) { $details += [string]$Result.agent.agentDetail }
    if ($Result.agent.llmDetail) { $details += [string]$Result.agent.llmDetail }
    if ($Result.agent.usageDetail) { $details += [string]$Result.agent.usageDetail }
  }

  if ($Result.checks) {
    foreach ($check in @($Result.checks)) {
      if ($check.detail) { $details += [string]$check.detail }
    }
  }

  $detailText = $details -join " "

  if ($detailText -match "HMB_AGENT_API_KEY") {
    $hints += "Set HMB_AGENT_API_KEY before starting Bridge if Hermes Agent requires auth for models or token usage."
  }

  if ($detailText -match "not reachable") {
    $hints += "Start Hermes Agent Gateway, or set HMB_AGENT_URL to the correct local Agent URL before starting Bridge."
  }

  if (
    ($Result.capabilities -and $Result.capabilities.usage -ne "ok") -or
    ($detailText -match "/v1/usage/summary")
  ) {
    $hints += "Token usage is optional for chat. It only affects Dashboard usage display and diagnostics."
  }

  if (
    ($Result.capabilities -and $Result.capabilities.memory -ne "ok") -or
    ($detailText -match "memory status")
  ) {
    $hints += "Memory diagnostics are read-only. If your Agent exposes a memory status endpoint, set HMB_MEMORY_STATUS_PATHS before starting Bridge."
  }

  if (
    $Result.capabilities -and
    (
      $Result.capabilities.runs -eq "unavailable" -or
      $Result.capabilities.sse -eq "unavailable" -or
      $Result.capabilities.stop -eq "unavailable" -or
      $Result.capabilities.approval -eq "unavailable"
    )
  ) {
    $hints += "Bridge intentionally does not take over chat traffic in Phase 1. Keep Hermes Mobile chat pointed at Hermes Agent Gateway."
  }

  return $hints | Select-Object -Unique
}

function Write-BridgeSetupHints {
  param($Result)

  $hints = @(Get-BridgeSetupHints $Result)
  if ($hints.Count -eq 0) {
    return
  }

  Write-Host ""
  Write-Host "Next steps:"
  for ($index = 0; $index -lt $hints.Count; $index++) {
    Write-Host "  $($index + 1). $($hints[$index])"
  }
}

function Read-PairingQrPayload {
  param([string]$QrPayload)

  try {
    $uri = [Uri]::new($QrPayload)
    if ($uri.Scheme -ne "hmb" -or $uri.Host -ne "pair") {
      return $null
    }

    $values = @{}
    $query = $uri.Query.TrimStart("?")
    foreach ($part in ($query -split "&")) {
      if (-not $part) {
        continue
      }

      $pieces = $part -split "=", 2
      $key = [Uri]::UnescapeDataString($pieces[0])
      $value = if ($pieces.Count -gt 1) { [Uri]::UnescapeDataString($pieces[1]) } else { "" }
      $values[$key] = $value
    }

    if ($values.v -ne "1") {
      return $null
    }

    return [pscustomobject]@{
      b = $values.b
      c = $values.c
    }
  } catch {
    return $null
  }
}

function Write-PairingQr {
  param([string]$QrPayload)

  $encodedPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($QrPayload))
  $nodeScript = @"
const payload = Buffer.from(process.argv[1], 'base64').toString('utf8');
const qrcode = (await import('qrcode-terminal')).default;
qrcode.generate(payload, { small: true });
"@

  Write-Host "Scan with Hermes Mobile:"
  Push-Location $ScriptDir
  try {
    $qrOutput = & node --input-type=module -e $nodeScript $encodedPayload 2>&1
    if ($LASTEXITCODE -ne 0) {
      $log = ($qrOutput | Out-String).Trim()
      throw "qrcode-terminal failed: $log"
    }

    $qrOutput | ForEach-Object { Write-Host $_ }
    Write-Host ""
  } catch {
    Write-Host "QR rendering unavailable. Pair manually with the Gateway URL and Pairing Code above."
    Write-Host $_.Exception.Message
    Write-Host ""
  } finally {
    Pop-Location
  }
}

$NodeVersion = Test-Node

if ($Command -eq "start") {
  $SelectedPort = Resolve-BridgePort $Port
  $GatewayUrl = Get-LocalGatewayUrl $SelectedPort

  if ($SelectedPort -ne $Port) {
    Write-Host "Port $Port is busy. Using port $SelectedPort instead."
  }

  Write-Host "Node.js: $NodeVersion"
  Write-Host "Install dir: $ScriptDir"
  Write-Host "Gateway URL: $GatewayUrl"
  Write-NetworkHelp $GatewayUrl $SelectedPort
  Ensure-AgentApiKeyForPairing

  $env:HMB_PORT = "$SelectedPort"
  $env:HMB_PUBLIC_URL = $GatewayUrl
  node $Server
  exit $LASTEXITCODE
}

if ($Command -eq "doctor" -or $Command -eq "status") {
  $url = "http://127.0.0.1:$Port/v1/local/status"
  try {
    $result = Invoke-RestMethod -Method GET -Uri $url -TimeoutSec 5
    Write-Host "Hermes Mobile Bridge status"
    Write-Host ""
    Write-Host "Status: $($result.status)"
    Write-Host "Version: $($result.version)"
    Write-Host "Gateway URL: $($result.gatewayUrl)"
    Write-Host "Pairing available: $($result.pairing.available)"
    if ($result.pairing.expiresInSeconds -ne $null) {
      Write-Host "Pairing expires in: $($result.pairing.expiresInSeconds)s"
    }
    Write-BridgeCapabilities $result.capabilities
    Write-BridgeChecks $result.checks
    Write-BridgeSetupHints $result
    if ($result.network) {
      Write-Host ""
      Write-Host "Network:"
      Write-Host "  Local health: $($result.network.localHealthUrl)"
      Write-Host "  Phone URL: $($result.network.phoneUrl)"
      Write-Host "  LAN IP: $($result.network.lanIp)"
      Write-Host "  Listen host: $($result.network.listenHost)"
      Write-Host "  Firewall: $(Get-FirewallHint $Port)"
      Write-Host ""
      Write-Host "If the phone cannot connect, keep Bridge running and check same Wi-Fi/VPN plus Windows Firewall private-network access for Node.js."
    }
  } catch {
    Write-Host "Hermes Mobile Bridge is not reachable at $url"
    Write-Host $_.Exception.Message
    exit 1
  }
}

if ($Command -eq "qr") {
  $url = "http://127.0.0.1:$Port/v1/local/status"
  try {
    $result = Invoke-RestMethod -Method GET -Uri $url -TimeoutSec 5

    if (-not $result.pairing -or -not $result.pairing.available) {
      Write-Host "Hermes Mobile Bridge pairing QR is not available."
      if ($result.pairing -and $result.pairing.used) {
        Write-Host "Pairing code has already been used."
      } elseif ($result.pairing -and $result.pairing.expiresInSeconds -le 0) {
        Write-Host "Pairing code has expired."
      }
      Write-Host "Restart Bridge with: .\hermes-mobile.ps1 start -Port $Port"
      exit 1
    }

    if (-not $result.pairing.qrPayload) {
      Write-Host "Bridge did not return a QR payload. Update or restart Hermes Mobile Bridge, then retry."
      exit 1
    }

    $payload = Read-PairingQrPayload $result.pairing.qrPayload
    if (-not $payload -or -not $payload.b -or -not $payload.c) {
      Write-Host "Bridge returned an invalid QR payload. Restart Hermes Mobile Bridge, then retry."
      exit 1
    }

    Write-Host "Hermes Mobile Bridge pairing QR"
    Write-Host ""
    Write-Host "Gateway URL: $($payload.b)"
    Write-Host "Pairing Code: $($payload.c)"
    if ($result.pairing.expiresInSeconds -ne $null) {
      Write-Host "Pairing expires in: $($result.pairing.expiresInSeconds)s"
    }
    Write-Host ""
    Write-PairingQr $result.pairing.qrPayload
    Write-Host "Or pair manually with the values above."
  } catch {
    Write-Host "Hermes Mobile Bridge is not reachable at $url"
    Write-Host $_.Exception.Message
    exit 1
  }
}
