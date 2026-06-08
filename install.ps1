param(
  [ValidateSet("start", "doctor", "status")]
  [string]$Command = "start",
  [int]$Port = 8642
)

$ErrorActionPreference = "Stop"

$BridgePayloadRef = "ca4a4f4df6eb749e00f9b5765e97a97d05885018"
$RepoRawBase = "https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/$BridgePayloadRef"
$InstallRoot = Join-Path $env:LOCALAPPDATA "HermesMobileBridge"
$InstallRequestId = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$Files = @(
  "package.json",
  "package-lock.json",
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

function Test-NodeForInstall {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) {
    throw "Node.js is required before installing Hermes Mobile Bridge dependencies. Install the LTS version from https://nodejs.org/en/download, then run this command again."
  }

  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $npm) {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
  }

  if (-not $npm) {
    throw "npm was not found. Install Node.js LTS from https://nodejs.org/en/download, then run this command again."
  }

  return @{
    NodeVersion = (& node --version)
    NpmCommand = $npm.Source
  }
}

function Install-NodeDependencies {
  param([string]$NpmCommand)

  $packageLock = Join-Path $InstallRoot "package-lock.json"
  if (-not (Test-Path $packageLock)) {
    throw "Cannot install Hermes Mobile Bridge dependencies because package-lock.json is missing from $InstallRoot."
  }

  Write-Host "Installing Node dependencies with npm ci..."
  Push-Location $InstallRoot
  try {
    $npmOutput = & $NpmCommand ci --omit=dev --no-audit --no-fund 2>&1
    if ($LASTEXITCODE -ne 0) {
      $log = ($npmOutput | Out-String).Trim()
      throw "npm ci failed. Hermes Mobile Bridge will not start until dependencies install successfully.`n$log"
    }
  } finally {
    Pop-Location
  }
}

Install-BridgeFiles
$InstallTools = Test-NodeForInstall
Install-NodeDependencies $InstallTools.NpmCommand

$Launcher = Join-Path $InstallRoot "hermes-mobile.ps1"
if (-not (Test-Path $Launcher)) {
  throw "Cannot find installed launcher: $Launcher"
}

Write-Host "Hermes Mobile Bridge installed at $InstallRoot"
Write-Host ""
& $Launcher $Command -Port $Port
