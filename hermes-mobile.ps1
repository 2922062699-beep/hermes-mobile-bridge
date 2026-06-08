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

  return "http://$ip`:$SelectedPort"
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
  Write-Host ""

  $env:HMB_PORT = "$SelectedPort"
  $env:HMB_PUBLIC_URL = $GatewayUrl
  node $Server
  exit $LASTEXITCODE
}

if ($Command -eq "doctor" -or $Command -eq "status") {
  $url = "http://127.0.0.1:$Port/health/detailed"
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
    Write-Host ""
    Write-Host "Capabilities:"
    $result.capabilities.PSObject.Properties | ForEach-Object {
      Write-Host "  $($_.Name): $($_.Value)"
    }
  } catch {
    Write-Host "Hermes Mobile Bridge is not reachable at $url"
    Write-Host $_.Exception.Message
    exit 1
  }
}
