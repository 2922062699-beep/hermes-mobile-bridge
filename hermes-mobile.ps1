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
}

function Get-LocalGatewayUrl {
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

  return "http://$ip`:$Port"
}

Test-Node

if ($Command -eq "start") {
  $env:HMB_PORT = "$Port"
  $env:HMB_PUBLIC_URL = Get-LocalGatewayUrl
  node $Server
  exit $LASTEXITCODE
}

if ($Command -eq "doctor" -or $Command -eq "status") {
  $url = "http://127.0.0.1:$Port/health/detailed"
  try {
    $result = Invoke-RestMethod -Method GET -Uri $url -TimeoutSec 5
    $result | ConvertTo-Json -Depth 8
  } catch {
    Write-Host "Hermes Mobile Bridge is not reachable at $url"
    Write-Host $_.Exception.Message
    exit 1
  }
}
