param(
  [ValidateSet("start", "stop", "status", "index")]
  [string]$Command = "status",
  [string]$InstallRoot = "$env:USERPROFILE\.activity2context",
  [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $InstallRoot "config.json"
}

$runDir = Join-Path $InstallRoot "run"
$observerPidFile = Join-Path $runDir "observer.pid"
$indexerPidFile = Join-Path $runDir "indexer.pid"
$indexerStopFlag = Join-Path $runDir "indexer.stop.flag"

$observerScript = Join-Path $InstallRoot "runtime\windows\activity2context-observer.ps1"
$indexerScript = Join-Path $InstallRoot "runtime\windows\activity2context-entity-indexer.ps1"
$indexerLoopScript = Join-Path $InstallRoot "runtime\windows\activity2context-indexer-loop.ps1"

function Ensure-RunDir {
  if (-not (Test-Path $runDir)) {
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
  }
}

function Get-AlivePid([string]$pidFile) {
  if (-not (Test-Path $pidFile)) { return $null }
  $txt = (Get-Content -Raw -Path $pidFile).Trim()
  $txt = ($txt -replace '[^\d]', '')
  if (-not $txt) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    return $null
  }
  $pidValue = 0
  if (-not [int]::TryParse($txt, [ref]$pidValue)) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    return $null
  }
  $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
  if (-not $proc) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    return $null
  }
  return $pidValue
}

function Save-Pid([string]$pidFile, [int]$pidValue) {
  Set-Content -Path $pidFile -Value $pidValue -Encoding ASCII
}

if (-not (Test-Path $ConfigPath)) {
  throw "Config not found: $ConfigPath"
}
if (-not (Test-Path $observerScript)) {
  throw "Observer script not found: $observerScript"
}
if (-not (Test-Path $indexerScript)) {
  throw "Indexer script not found: $indexerScript"
}
if (-not (Test-Path $indexerLoopScript)) {
  throw "Indexer loop script not found: $indexerLoopScript"
}

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$behaviorDir = [System.IO.Path]::GetDirectoryName([string]$config.behaviorLog)
$observerStopFlag = Join-Path $behaviorDir "stop.flag"

Ensure-RunDir

switch ($Command) {
  "start" {
    if (-not (Test-Path $behaviorDir)) {
      New-Item -ItemType Directory -Path $behaviorDir -Force | Out-Null
    }

    if (Test-Path $observerStopFlag) {
      Remove-Item $observerStopFlag -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $indexerStopFlag) {
      Remove-Item $indexerStopFlag -Force -ErrorAction SilentlyContinue
    }

    $observerPid = Get-AlivePid $observerPidFile
    if (-not $observerPid) {
      $observerArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $observerScript,
        "-Workspace", [string]$config.workspace,
        "-LogFile", [string]$config.behaviorLog,
        "-EntitiesLog", [string]$config.entitiesLog,
        "-BrowserThreshold", [string]$config.observer.browserThreshold,
        "-BrowserUpdateInterval", [string]$config.observer.browserUpdateInterval,
        "-AppThreshold", [string]$config.observer.appThreshold,
        "-AppUpdateInterval", [string]$config.observer.appUpdateInterval,
        "-PollSeconds", [string]$config.observer.pollSeconds
      )
      $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $observerArgs -WindowStyle Hidden -PassThru
      Save-Pid -pidFile $observerPidFile -pidValue $proc.Id
      $observerPid = $proc.Id
    }

    $indexerPid = Get-AlivePid $indexerPidFile
    if (-not $indexerPid) {
      $idxArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $indexerLoopScript,
        "-InstallRoot", $InstallRoot,
        "-ConfigPath", $ConfigPath
      )
      $proc2 = Start-Process -FilePath "powershell.exe" -ArgumentList $idxArgs -WindowStyle Hidden -PassThru
      Save-Pid -pidFile $indexerPidFile -pidValue $proc2.Id
      $indexerPid = $proc2.Id
    }

    [pscustomobject]@{
      command = "start"
      observerPid = $observerPid
      indexerPid = $indexerPid
      behaviorLog = [string]$config.behaviorLog
      entitiesLog = [string]$config.entitiesLog
    } | ConvertTo-Json -Depth 4
    break
  }

  "stop" {
    Set-Content -Path $observerStopFlag -Value "stop" -Encoding UTF8
    Set-Content -Path $indexerStopFlag -Value "stop" -Encoding UTF8

    $observerPid = Get-AlivePid $observerPidFile
    $indexerPid = Get-AlivePid $indexerPidFile

    Start-Sleep -Seconds 2

    if ($observerPid) {
      $p = Get-Process -Id $observerPid -ErrorAction SilentlyContinue
      if ($p) { Stop-Process -Id $observerPid -Force -ErrorAction SilentlyContinue }
    }
    if ($indexerPid) {
      $p2 = Get-Process -Id $indexerPid -ErrorAction SilentlyContinue
      if ($p2) { Stop-Process -Id $indexerPid -Force -ErrorAction SilentlyContinue }
    }

    for ($i = 0; $i -lt 5; $i++) {
      $obsAlive = if ($observerPid) { Get-Process -Id $observerPid -ErrorAction SilentlyContinue } else { $null }
      $idxAlive = if ($indexerPid) { Get-Process -Id $indexerPid -ErrorAction SilentlyContinue } else { $null }
      if (-not $obsAlive -and -not $idxAlive) { break }
      Start-Sleep -Seconds 1
    }

    Remove-Item $observerPidFile -Force -ErrorAction SilentlyContinue
    Remove-Item $indexerPidFile -Force -ErrorAction SilentlyContinue
    Remove-Item $indexerStopFlag -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
      command = "stop"
      observerStopped = $true
      indexerStopped = $true
    } | ConvertTo-Json -Depth 4
    break
  }

  "status" {
    $observerPid = Get-AlivePid $observerPidFile
    $indexerPid = Get-AlivePid $indexerPidFile

    [pscustomobject]@{
      command = "status"
      observerRunning = [bool]$observerPid
      observerPid = $observerPid
      indexerRunning = [bool]$indexerPid
      indexerPid = $indexerPid
      behaviorLog = [string]$config.behaviorLog
      entitiesLog = [string]$config.entitiesLog
      workspace = [string]$config.workspace
    } | ConvertTo-Json -Depth 4
    break
  }

  "index" {
    & $indexerScript `
      -InputLog $config.behaviorLog `
      -OutputFile $config.entitiesLog `
      -MinDurationSeconds ([int]$config.indexer.minDurationSeconds) `
      -MaxAgeMinutes ([int]$config.indexer.maxAgeMinutes) `
      -MaxTotal ([int]$config.indexer.maxTotal) `
      -MaxWeb ([int]$config.indexer.maxWeb) `
      -MaxDoc ([int]$config.indexer.maxDoc) `
      -MaxApp ([int]$config.indexer.maxApp)

    [pscustomobject]@{
      command = "index"
      output = [string]$config.entitiesLog
    } | ConvertTo-Json -Depth 4
    break
  }
}
