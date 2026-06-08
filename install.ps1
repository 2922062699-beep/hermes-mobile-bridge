param(
  [string]$Command = "start"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $ScriptDir "hermes-mobile.ps1"

if (-not (Test-Path $Launcher)) {
  throw "Cannot find hermes-mobile.ps1 next to install.ps1"
}

& $Launcher $Command
