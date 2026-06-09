param(
  [ValidateSet("start", "doctor", "status")]
  [string]$Command = "start",
  [int]$Port = 8642
)

$ErrorActionPreference = "Stop"

$BridgePayloadRef = "0da832b01516392c19af566c8144f4c6cab3cec9"
$JsdelivrBase = "https://cdn.jsdelivr.net/gh/2922062699-beep/hermes-mobile-bridge@$BridgePayloadRef"
$RawBase = "https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/$BridgePayloadRef"
$GhproxyBase = "https://ghproxy.com/$RawBase"
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
  $downloadPath = $RelativePath -replace '\\','/'
  if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }

  Write-Host "Downloading $RelativePath"
  $sources = @(
    @{ Name = "jsDelivr"; Url = "$JsdelivrBase/$downloadPath?v=$InstallRequestId" },
    @{ Name = "GitHub raw"; Url = "$RawBase/$downloadPath?v=$InstallRequestId" },
    @{ Name = "ghproxy"; Url = "$GhproxyBase/$downloadPath?v=$InstallRequestId" }
  )
  $errors = @()

  foreach ($source in $sources) {
    if (Test-Path $target) {
      Remove-Item -LiteralPath $target -Force
    }

    try {
      Invoke-WebRequest -UseBasicParsing -Uri $source.Url -OutFile $target -TimeoutSec 30
      if (Test-Path $target) {
        Write-Host "  OK: $($source.Name)"
        return
      }
      $errors += "$($source.Name): download finished but file is missing"
    } catch {
      $errors += "$($source.Name): $($_.Exception.Message)"
    }
  }

  $detail = ($errors | ForEach-Object { "  - $_" }) -join "`n"
  throw "Failed to download $RelativePath from all payload mirrors.`n$detail`nTry again later, or manually git clone https://github.com/2922062699-beep/hermes-mobile-bridge and run the launcher locally."
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
