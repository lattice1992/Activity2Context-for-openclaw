param(
  [string]$InstallRoot = "$env:USERPROFILE\.activity2context",
  [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $InstallRoot "config.json"
}

$runDir = Join-Path $InstallRoot "run"
if (-not (Test-Path $runDir)) {
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null
}

$stopFlag = Join-Path $runDir "indexer.stop.flag"
$indexerScript = Join-Path $InstallRoot "runtime\windows\activity2context-entity-indexer.ps1"

if (-not (Test-Path $ConfigPath)) {
  throw "Config not found: $ConfigPath"
}
if (-not (Test-Path $indexerScript)) {
  throw "Indexer script not found: $indexerScript"
}

Write-Host "[activity2context] indexer loop started" -ForegroundColor Green

while ($true) {
  if (Test-Path $stopFlag) {
    Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue
    break
  }

  try {
    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $interval = [int]$config.indexer.intervalSeconds
    if ($interval -lt 5) { $interval = 5 }

    & $indexerScript `
      -InputLog $config.behaviorLog `
      -OutputFile $config.entitiesLog `
      -MinDurationSeconds ([int]$config.indexer.minDurationSeconds) `
      -MaxAgeMinutes ([int]$config.indexer.maxAgeMinutes) `
      -MaxTotal ([int]$config.indexer.maxTotal) `
      -MaxWeb ([int]$config.indexer.maxWeb) `
      -MaxDoc ([int]$config.indexer.maxDoc) `
      -MaxApp ([int]$config.indexer.maxApp)
  } catch {
    Write-Host "[activity2context] indexer loop error: $($_.Exception.Message)" -ForegroundColor Yellow
    $interval = 15
  }

  for ($i = 0; $i -lt $interval; $i++) {
    if (Test-Path $stopFlag) {
      Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue
      break
    }
    Start-Sleep -Seconds 1
  }

  if (-not (Test-Path $stopFlag)) { continue }
  break
}

Write-Host "[activity2context] indexer loop stopped" -ForegroundColor Yellow
