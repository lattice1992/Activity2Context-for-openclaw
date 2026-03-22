param(
  [string]$InputLog = "$env:USERPROFILE\.activity2context\data\activity2context_behavior.md",
  [string]$OutputFile = "$env:USERPROFILE\.activity2context\data\activity2context_entities.md",
  [int]$MinDurationSeconds = 10,
  [int]$MaxAgeMinutes = 60,
  [int]$MaxTotal = 10,
  [int]$MaxWeb = 3,
  [int]$MaxDoc = 4,
  [int]$MaxApp = 3
)

$ErrorActionPreference = "Stop"

function Normalize-AppName([string]$app) {
  if (-not $app) { return "" }
  $x = $app.Trim().ToLower()
  if ($x.EndsWith(".exe")) { $x = $x.Substring(0, $x.Length - 4) }
  return $x
}

function Parse-LogTime([string]$timeText, [datetime]$now) {
  $dt = [datetime]::ParseExact(
    "$($now.ToString('yyyy-MM-dd')) $timeText",
    "yyyy-MM-dd HH:mm:ss",
    [System.Globalization.CultureInfo]::InvariantCulture
  )
  if ($dt -gt $now.AddMinutes(1)) {
    return $dt.AddDays(-1)
  }
  return $dt
}

function Clean([string]$value) {
  if (-not $value) { return "" }
  return (($value -replace "\r?\n", " ") -replace "\s+", " ").Trim()
}

function Ensure-Entity([hashtable]$map, [string]$key, [string]$type) {
  if (-not $map.ContainsKey($key)) {
    $map[$key] = [pscustomobject]@{
      Type = $type
      Key = $key
      Title = ""
      URL = ""
      Name = ""
      Path = ""
      App = ""
      DurationSum = 0
      LastActive = [datetime]::MinValue
      ActionCount = 0
    }
  }
  return $map[$key]
}

if (-not (Test-Path $InputLog)) {
  throw "Input log not found: $InputLog"
}

$now = Get-Date
$cutoff = $now.AddMinutes(-$MaxAgeMinutes)

$appBlacklist = @("explorer", "taskmgr", "desktop")

$webMap = @{}
$docMap = @{}
$appMap = @{}

$linePattern = '^\* \[(?<time>\d{2}:\d{2}:\d{2})\] \*\*(?<type>[A-Z]+)\*\*: (?<details>.+)$'
$browserPattern = '^(?<mode>Stay|Focus):(?<sec>\d+)s \| Title:(?<title>.*?) \| URL:(?<url>.+)$'
$appPattern = '^(?<mode>Stay|Focus):(?<sec>\d+)s \| App:(?<app>[^|]+) \| Title:(?<title>[^|]*)(?: \| RecentDoc:(?<doc>.+))?$'
$docPattern = '^Action:(?<action>\w+) \| Name:(?<name>.*?) \| Path:(?<path>.+)$'

$lines = Get-Content -Path $InputLog -Encoding UTF8
foreach ($line in $lines) {
  if ($line -notmatch $linePattern) { continue }

  $eventTime = Parse-LogTime -timeText $Matches.time -now $now
  $type = $Matches.type
  $details = $Matches.details

  switch ($type) {
    "BROWSER" {
      if ($details -notmatch $browserPattern) { continue }
      $sec = [int]$Matches.sec
      $title = Clean $Matches.title
      $url = Clean $Matches.url
      if (-not $url -or $url -eq "URL Unknown") { continue }

      $key = $url.ToLower()
      $e = Ensure-Entity -map $webMap -key $key -type "Web"
      $e.URL = $url
      if ($title) { $e.Title = $title }
      $e.DurationSum += $sec
      if ($eventTime -gt $e.LastActive) { $e.LastActive = $eventTime }
      continue
    }
    "APP" {
      if ($details -notmatch $appPattern) { continue }
      $sec = [int]$Matches.sec
      $appRaw = Clean $Matches.app
      $appNorm = Normalize-AppName $appRaw
      if (-not $appNorm) { continue }

      if ($appBlacklist -contains $appNorm) { continue }

      $title = Clean $Matches.title
      $appEntity = Ensure-Entity -map $appMap -key $appNorm -type "App"
      $appEntity.App = $appRaw
      if ($title) { $appEntity.Title = $title }
      $appEntity.DurationSum += $sec
      if ($eventTime -gt $appEntity.LastActive) { $appEntity.LastActive = $eventTime }

      $recentDoc = Clean $Matches.doc
      if ($recentDoc) {
        $docKey = $recentDoc.ToLower()
        $docEntity = Ensure-Entity -map $docMap -key $docKey -type "Doc"
        $docEntity.Path = $recentDoc
        $docEntity.Name = [System.IO.Path]::GetFileName($recentDoc)
        $docEntity.DurationSum += $sec
        if ($eventTime -gt $docEntity.LastActive) { $docEntity.LastActive = $eventTime }
      }
      continue
    }
    "DOCUMENT" {
      if ($details -notmatch $docPattern) { continue }
      $action = Clean $Matches.action
      $name = Clean $Matches.name
      $path = Clean $Matches.path
      if (-not $path) { continue }

      $docKey = $path.ToLower()
      $docEntity = Ensure-Entity -map $docMap -key $docKey -type "Doc"
      $docEntity.Path = $path
      if ($name) {
        $docEntity.Name = [System.IO.Path]::GetFileName($name)
      } elseif (-not $docEntity.Name) {
        $docEntity.Name = [System.IO.Path]::GetFileName($path)
      }
      if ($action -ieq "Changed") { $docEntity.ActionCount += 1 }
      if ($eventTime -gt $docEntity.LastActive) { $docEntity.LastActive = $eventTime }
      continue
    }
  }
}

$webEntities = @(
  $webMap.Values |
    Where-Object { $_.LastActive -ge $cutoff -and $_.DurationSum -ge $MinDurationSeconds } |
    Sort-Object LastActive -Descending
)

$docEntities = @(
  $docMap.Values |
    Where-Object {
      $_.LastActive -ge $cutoff -and
      $_.Path -and
      $_.DurationSum -ge $MinDurationSeconds
    } |
    Sort-Object LastActive -Descending
)

$appEntities = @(
  $appMap.Values |
    Where-Object { $_.LastActive -ge $cutoff -and $_.DurationSum -ge $MinDurationSeconds } |
    Sort-Object LastActive -Descending
)

$selectedWeb = @($webEntities | Select-Object -First $MaxWeb)
$selectedDoc = @($docEntities | Select-Object -First $MaxDoc)
$selectedApp = @($appEntities | Select-Object -First $MaxApp)
$selected = @($selectedWeb + $selectedDoc + $selectedApp)

if ($selected.Count -lt $MaxTotal) {
  $selectedKeyMap = @{}
  foreach ($e in $selected) {
    $selectedKeyMap["$($e.Type)|$($e.Key)"] = $true
  }

  $leftovers = @(
    @($webEntities + $docEntities + $appEntities) |
      Where-Object { -not $selectedKeyMap.ContainsKey("$($_.Type)|$($_.Key)") } |
      Sort-Object LastActive -Descending
  )

  $need = $MaxTotal - $selected.Count
  if ($need -gt 0 -and $leftovers.Count -gt 0) {
    $selected += @($leftovers | Select-Object -First $need)
  }
}

$selected = @($selected | Sort-Object LastActive -Descending | Select-Object -First $MaxTotal)
$selectedWeb = @($selected | Where-Object { $_.Type -eq "Web" } | Sort-Object LastActive -Descending)
$selectedDoc = @($selected | Where-Object { $_.Type -eq "Doc" } | Sort-Object LastActive -Descending)
$selectedApp = @($selected | Where-Object { $_.Type -eq "App" } | Sort-Object LastActive -Descending)

$outLines = New-Object System.Collections.Generic.List[string]
$outLines.Add("[ACTIVITY2CONTEXT ENTITIES]")

$webIdx = 0
$docIdx = 0
$appIdx = 0
foreach ($e in $selected) {
  if ($e.Type -eq "Web") {
    $webIdx += 1
    $outLines.Add("- ID: Web_$webIdx | Title: $(Clean $e.Title) | Time: $($e.DurationSum)s | URL: $(Clean $e.URL)")
    continue
  }
  if ($e.Type -eq "Doc") {
    $docIdx += 1
    $name = if ($e.Name) { $e.Name } else { [System.IO.Path]::GetFileName($e.Path) }
    $outLines.Add("- ID: Doc_$docIdx | Name: $(Clean $name) | Edits: $($e.ActionCount) | Path: $(Clean $e.Path)")
    continue
  }
  if ($e.Type -eq "App") {
    $appIdx += 1
    $active = $e.LastActive.ToString("yyyy-MM-dd HH:mm:ss")
    $outLines.Add("- ID: App_$appIdx | Name: $(Clean $e.App) | Time: $($e.DurationSum)s | Active: $active")
    continue
  }
}

if ($outLines.Count -eq 1) {
  $outLines.Add("- (no active entities in the last $MaxAgeMinutes minutes)")
}

$outputDir = [System.IO.Path]::GetDirectoryName($OutputFile)
if ($outputDir -and -not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir | Out-Null
}

Set-Content -Path $OutputFile -Value $outLines -Encoding UTF8
Write-Host "Entity index generated: $OutputFile" -ForegroundColor Green
Write-Host "Selected: web=$($selectedWeb.Count) doc=$($selectedDoc.Count) app=$($selectedApp.Count) total=$($selected.Count)" -ForegroundColor Green
