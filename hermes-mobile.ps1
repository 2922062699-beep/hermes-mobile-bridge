param(
  [ValidateSet("start", "doctor", "status")]
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
