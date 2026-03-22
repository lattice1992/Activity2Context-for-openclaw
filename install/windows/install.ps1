param(
  [string]$Workspace = (Get-Location).Path,
  [string]$InstallRoot = "$env:USERPROFILE\.activity2context",
  [switch]$NoAutoStart,
  [switch]$NoStartNow
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runtimeSrc = Join-Path $repoRoot "runtime"
$integrationsSrc = Join-Path $repoRoot "integrations"

if (-not (Test-Path $runtimeSrc)) {
  throw "Runtime folder not found: $runtimeSrc"
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "data") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "run") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "runtime") -Force | Out-Null

Copy-Item -Path (Join-Path $runtimeSrc "*") -Destination (Join-Path $InstallRoot "runtime") -Recurse -Force
if (Test-Path $integrationsSrc) {
  New-Item -ItemType Directory -Path (Join-Path $InstallRoot "integrations") -Force | Out-Null
  Copy-Item -Path (Join-Path $integrationsSrc "*") -Destination (Join-Path $InstallRoot "integrations") -Recurse -Force
}

$configPath = Join-Path $InstallRoot "config.json"
if (-not (Test-Path $configPath)) {
  $defaultConfig = [ordered]@{
    workspace = $Workspace
    behaviorLog = (Join-Path $Workspace ".openclaw\activity2context_behavior.md")
    entitiesLog = (Join-Path $Workspace "activity2context\memory.md")
    observer = [ordered]@{
      pollSeconds = 2
      browserThreshold = 5
      browserUpdateInterval = 10
      appThreshold = 5
      appUpdateInterval = 10
      maxBehaviorLines = 5000
    }
    indexer = [ordered]@{
      intervalSeconds = 60
      minDurationSeconds = 10
      maxAgeMinutes = 60
      maxTotal = 10
      maxWeb = 3
      maxDoc = 4
      maxApp = 3
    }
  }
  $defaultConfig | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
}

$launcherCmd = @"
@echo off
setlocal
set INSTALL_ROOT=%~dp0
if "%~1"=="" (
  set CMD=status
) else (
  set CMD=%~1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_ROOT%runtime\windows\activity2contextctl.ps1" -Command %CMD% -InstallRoot "%INSTALL_ROOT:~0,-1%"
endlocal
"@
Set-Content -Path (Join-Path $InstallRoot "activity2context.cmd") -Value $launcherCmd -Encoding ASCII

$startupDir = [Environment]::GetFolderPath("Startup")
$startupFile = Join-Path $startupDir "activity2context-start.cmd"
if (-not $NoAutoStart) {
  $startupCmd = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$InstallRoot\runtime\windows\activity2contextctl.ps1" -Command start -InstallRoot "$InstallRoot"
"@
  Set-Content -Path $startupFile -Value $startupCmd -Encoding ASCII
} else {
  Remove-Item -Path $startupFile -Force -ErrorAction SilentlyContinue
}

if (-not $NoStartNow) {
  & (Join-Path $InstallRoot "runtime\windows\activity2contextctl.ps1") -Command start -InstallRoot $InstallRoot | Out-Null
}

Write-Host "Activity2Context installed." -ForegroundColor Green
Write-Host "Install root: $InstallRoot" -ForegroundColor Green
Write-Host "Config: $configPath" -ForegroundColor Green
Write-Host ""
Write-Host "Run commands:" -ForegroundColor Cyan
Write-Host "  $InstallRoot\activity2context.cmd status"
Write-Host "  $InstallRoot\activity2context.cmd start"
Write-Host "  $InstallRoot\activity2context.cmd stop"
Write-Host "  $InstallRoot\activity2context.cmd index"
