param(
  [string]$InstallRoot = "$env:USERPROFILE\.activity2context",
  [switch]$KeepData
)

$ErrorActionPreference = "Stop"

$ctl = Join-Path $InstallRoot "runtime\windows\activity2contextctl.ps1"
if (Test-Path $ctl) {
  try {
    & $ctl -Command stop -InstallRoot $InstallRoot | Out-Null
  } catch {}
}

$startupDir = [Environment]::GetFolderPath("Startup")
$startupFile = Join-Path $startupDir "activity2context-start.cmd"
Remove-Item -Path $startupFile -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $InstallRoot)) {
  Write-Host "Nothing to uninstall at $InstallRoot" -ForegroundColor Yellow
  exit 0
}

if ($KeepData) {
  Remove-Item -Path (Join-Path $InstallRoot "runtime") -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -Path (Join-Path $InstallRoot "integrations") -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -Path (Join-Path $InstallRoot "activity2context.cmd") -Force -ErrorAction SilentlyContinue
  Write-Host "Activity2Context runtime removed; data retained in $InstallRoot\data" -ForegroundColor Green
} else {
  Remove-Item -Path $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Activity2Context fully uninstalled: $InstallRoot" -ForegroundColor Green
}
