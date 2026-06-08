param(
  [ValidateSet("start", "doctor", "status")]
  [string]$Command = "start",
  [int]$Port = 8642
)

$ErrorActionPreference = "Stop"

$BridgePayloadRef = "c2a938c0410a000a978022a9e0e5da3937c40df8"
$RepoRawBase = "https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/$BridgePayloadRef"
$InstallRoot = Join-Path $env:LOCALAPPDATA "HermesMobileBridge"
$InstallRequestId = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$Files = @(
  "package.json",
  "hermes-mobile.ps1",
  "bridge/server.mjs",
  "docs/protocol.md",
  "docs/release.md",
  "docs/security.md",
  "docs/troubleshooting.md",
  "README.md"
)

function Save-BridgeFile {
  param([string]$RelativePath)

  $target = Join-Path $InstallRoot $RelativePath
  $targetDir = Split-Path -Parent $target
  if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }

  $url = "$RepoRawBase/$($RelativePath -replace '\\','/')?v=$InstallRequestId"
  Write-Host "Downloading $RelativePath"
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $target
  } catch {
    throw "Failed to download $RelativePath from $url. Check that GitHub raw content is reachable from this PC, then retry."
  }

  if (-not (Test-Path $target)) {
    throw "Download finished but file is missing: $target"
  }
}

function Install-BridgeFiles {
  if (-not (Test-Path $InstallRoot)) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
  }

  foreach ($file in $Files) {
    Save-BridgeFile $file
  }
}

Install-BridgeFiles

$Launcher = Join-Path $InstallRoot "hermes-mobile.ps1"
if (-not (Test-Path $Launcher)) {
  throw "Cannot find installed launcher: $Launcher"
}

Write-Host "Hermes Mobile Bridge installed at $InstallRoot"
Write-Host ""
& $Launcher $Command -Port $Port
