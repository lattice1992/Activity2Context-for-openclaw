param(
  [string]$InputLog = "$env:USERPROFILE\.activity2context\data\activity2context_behavior.md",
  [string]$OutputFile = "$env:USERPROFILE\.activity2context\data\activity2context_entities.md",
  [string]$SemanticOutputFile = "",
  [string]$AppAliasesJson = "{}",
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

function Clamp-Score([double]$score) {
  $x = $score
  if ($x -lt 0.05) { $x = 0.05 }
  if ($x -gt 0.99) { $x = 0.99 }
  return [Math]::Round($x, 2)
}

function Get-Duration-Bonus([int]$duration) {
  $bonus = 0.0
  if ($duration -gt 60) { $bonus += 0.05 }
  if ($duration -gt 300) { $bonus += 0.05 }
  return $bonus
}

function Get-Recency-Bonus([datetime]$lastActive, [datetime]$now) {
  if ($lastActive -ge $now.AddMinutes(-10)) { return 0.05 }
  return 0.0
}

function Get-PriorityScore([int]$duration, [datetime]$lastActive, [int]$actionCount, [datetime]$now) {
  $ageMinutes = [Math]::Max(0.0, (($now - $lastActive).TotalMinutes))
  $recencyNorm = if ($ageMinutes -ge 1440.0) { 0.0 } else { 1.0 - ($ageMinutes / 1440.0) }
  $durationNorm = [Math]::Min(1.0, ([double]$duration / 1800.0))
  $editNorm = [Math]::Min(1.0, ([double]$actionCount / 8.0))
  $score = (0.55 * $recencyNorm) + (0.35 * $durationNorm) + (0.10 * $editNorm)
  return [Math]::Round($score, 4)
}

function Parse-EventTime([string]$timeText, [datetime]$now) {
  if (-not $timeText) { return $now }
  $raw = $timeText.Trim()

  try {
    return [datetime]::ParseExact(
      $raw,
      "yyyy-MM-dd HH:mm:ss",
      [System.Globalization.CultureInfo]::InvariantCulture
    )
  } catch {}

  try {
    $dt = [datetime]::ParseExact(
      "$($now.ToString('yyyy-MM-dd')) $raw",
      "yyyy-MM-dd HH:mm:ss",
      [System.Globalization.CultureInfo]::InvariantCulture
    )
    if ($dt -gt $now.AddMinutes(1)) {
      return $dt.AddDays(-1)
    }
    return $dt
  } catch {
    return $now
  }
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
      RawApp = ""
      AliasType = ""
      AliasMatched = $false
      DurationSum = 0
      LastActive = [datetime]::MinValue
      ActionCount = 0
    }
  }
  return $map[$key]
}

function Parse-AppAliases([string]$jsonText) {
  $map = @{}
  if (-not $jsonText) { return $map }

  try {
    $obj = $jsonText | ConvertFrom-Json
  } catch {
    return $map
  }
  if (-not $obj) { return $map }

  foreach ($p in $obj.PSObject.Properties) {
    $norm = Normalize-AppName $p.Name
    if ($norm) {
      $map[$norm] = $p.Value
    }
  }
  return $map
}

function Resolve-AppAlias([hashtable]$aliasMap, [string]$appNorm, [string]$appRaw) {
  $display = Clean $appRaw
  if (-not $display) { $display = $appNorm }
  $aliasType = ""
  $matched = $false

  if ($aliasMap.ContainsKey($appNorm)) {
    $matched = $true
    $v = $aliasMap[$appNorm]

    if ($v -is [string]) {
      $candidate = Clean $v
      if ($candidate) { $display = $candidate }
    } else {
      if ($v -and ($v.PSObject.Properties.Name -contains "name")) {
        $candidate = Clean ([string]$v.name)
        if ($candidate) { $display = $candidate }
      }
      if ($v -and ($v.PSObject.Properties.Name -contains "type")) {
        $candidateType = Clean ([string]$v.type)
        if ($candidateType) { $aliasType = $candidateType.ToLower() }
      }
    }
  }

  return [pscustomobject]@{
    DisplayName = $display
    AliasType = $aliasType
    Matched = $matched
  }
}

function Classify-Web([string]$url, [string]$title) {
  $u = Clean $url
  $t = (Clean $title).ToLower()
  $domain = ""
  if ($u -match '^(?:https?://)?(?<d>[^/\s]+)') {
    $domain = $Matches.d.ToLower()
  }

  $type = "web"
  $strongSignal = $false
  $keywordSignal = $false

  if ($domain -match '(youtube\.com|youtu\.be|bilibili\.com|vimeo\.com|twitch\.tv)') {
    $type = "video"
    $strongSignal = $true
  } elseif ($domain -match '(docs\.|developer\.|readthedocs|stackoverflow\.com|stackexchange\.com)') {
    $type = "reference"
    $strongSignal = $true
  } elseif ($domain -match '(chatgpt\.com|claude\.ai|gemini\.google\.com|perplexity\.ai)') {
    $type = "chat"
    $strongSignal = $true
  } elseif ($domain -match '(figma\.com|miro\.com)') {
    $type = "design"
    $strongSignal = $true
  } elseif ($domain -match '(notion\.so|docs\.google\.com)') {
    $type = "document"
    $strongSignal = $true
  } elseif ($domain -match '(store\.steampowered\.com|steamcommunity\.com)') {
    $type = "game"
    $strongSignal = $true
  }

  if ($t -match '(video|watch|stream|playlist|episode|trailer)') {
    if ($type -eq "web") { $type = "video" }
    $keywordSignal = $true
  } elseif ($t -match '(doc|documentation|readme|wiki|guide|reference|manual)') {
    if ($type -eq "web") { $type = "reference" }
    $keywordSignal = $true
  } elseif ($t -match '(chatgpt|assistant|claude|gemini|copilot)') {
    if ($type -eq "web") { $type = "chat" }
    $keywordSignal = $true
  } elseif ($t -match '(notion|sheet|slides|spreadsheet|document)') {
    if ($type -eq "web") { $type = "document" }
    $keywordSignal = $true
  } elseif ($t -match '(steam|game|rpg|mmorpg|survival)') {
    if ($type -eq "web") { $type = "game" }
    $keywordSignal = $true
  }

  return [pscustomobject]@{
    Type = $type
    StrongSignal = $strongSignal
    KeywordSignal = $keywordSignal
    Domain = $domain
  }
}

function Classify-Doc([string]$path, [string]$name) {
  $p = (Clean $path).ToLower()
  $n = (Clean $name).ToLower()
  $ext = [System.IO.Path]::GetExtension($p).ToLower()

  $type = "document"
  $knownExt = $false
  $keywordSignal = $false

  $codeExt = @(".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".java", ".cs", ".cpp", ".c", ".h", ".hpp", ".rs", ".swift", ".kt", ".rb", ".php", ".sh", ".ps1", ".sql", ".json", ".yaml", ".yml", ".toml")
  $officeExt = @(".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx", ".pdf", ".txt", ".rtf")
  $designExt = @(".fig", ".sketch", ".xd")
  $mediaExt = @(".png", ".jpg", ".jpeg", ".gif", ".mp4", ".mov", ".avi", ".wav", ".mp3")

  if ($codeExt -contains $ext) {
    $type = "code"
    $knownExt = $true
  } elseif ($officeExt -contains $ext) {
    $type = "document"
    $knownExt = $true
  } elseif ($designExt -contains $ext) {
    $type = "design"
    $knownExt = $true
  } elseif ($mediaExt -contains $ext) {
    $type = "media"
    $knownExt = $true
  } elseif ($ext -eq ".md") {
    $type = "notes"
    $knownExt = $true
  }

  if (($p -match '\\src\\|\\app\\|\\lib\\|\\runtime\\|\\scripts\\') -or ($n -match '(readme|changelog|spec|design|plan)')) {
    $keywordSignal = $true
    if ($type -eq "document" -and $p -match '\\src\\|\\app\\|\\lib\\|\\runtime\\|\\scripts\\') {
      $type = "code"
    }
  }

  return [pscustomobject]@{
    Type = $type
    KnownExt = $knownExt
    KeywordSignal = $keywordSignal
    Extension = $ext
  }
}

function Classify-App([string]$appName, [string]$title, [string]$aliasType) {
  $n = (Clean $appName).ToLower()
  $t = (Clean $title).ToLower()
  $type = "app"
  $keywordSignal = $false
  $aliasTypeUsed = $false

  if ($aliasType) {
    $type = $aliasType.ToLower()
    $aliasTypeUsed = $true
  } elseif ($n -match '(steam|epic|battle\.net|origin|uplay|riot|game)') {
    $type = "game"
    $keywordSignal = $true
  } elseif ($n -match '(vscode|visual studio|codex|pycharm|idea|xcode|cursor|terminal|powershell|cmd)') {
    $type = "code"
    $keywordSignal = $true
  } elseif ($n -match '(chrome|edge|firefox|brave|safari)') {
    $type = "browser"
    $keywordSignal = $true
  } elseif ($n -match '(word|excel|powerpoint|notepad|obsidian|notion)') {
    $type = "document"
    $keywordSignal = $true
  } elseif ($n -match '(discord|telegram|slack|wechat|whatsapp)') {
    $type = "chat"
    $keywordSignal = $true
  }

  if (-not $keywordSignal -and $t) {
    if ($t -match '(game|steam|survival|fps|rpg|mmorpg)') {
      $type = "game"
      $keywordSignal = $true
    } elseif ($t -match '(vscode|visual studio|project|solution|terminal|powershell|cmd|code)') {
      $type = "code"
      $keywordSignal = $true
    } elseif ($t -match '(chat|discord|telegram|slack|whatsapp)') {
      $type = "chat"
      $keywordSignal = $true
    } elseif ($t -match '(doc|document|sheet|slides|note)') {
      $type = "document"
      $keywordSignal = $true
    }
  }

  return [pscustomobject]@{
    Type = $type
    KeywordSignal = $keywordSignal
    AliasTypeUsed = $aliasTypeUsed
  }
}

function Is-LowValueWeb([string]$url, [string]$title) {
  $u = (Clean $url).ToLower()
  $t = (Clean $title).ToLower()
  if (-not $u) { return $true }
  if ($u -eq "url unknown") { return $true }

  if (
    $u -match '^(about:blank|about:newtab)$' -or
    $u -match '^chrome://newtab/?$' -or
    $u -match '^edge://newtab/?$' -or
    $u -match '^newtab/?$'
  ) {
    return $true
  }

  if (
    $t -match '^(new tab|newtab|\u65b0\u6807\u7b7e\u9875|\u7121\u6a19\u984c|\u65e0\u6807\u9898|untitled|blank page)(\s*-\s*.*)?$' -or
    $t -match '(new tab|newtab|\u65b0\u6807\u7b7e\u9875|\u7121\u6a19\u984c|\u65e0\u6807\u9898|untitled|blank page)' -or
    $t -eq "about:blank"
  ) {
    return $true
  }
  return $false
}

function Score-Web([pscustomobject]$class, [int]$duration, [datetime]$lastActive, [datetime]$now) {
  $score = 0.30
  if ($class.StrongSignal) { $score += 0.30 }
  if ($class.KeywordSignal) { $score += 0.20 }
  $score += Get-Duration-Bonus $duration
  $score += Get-Recency-Bonus -lastActive $lastActive -now $now
  if ($class.Type -eq "web" -and -not $class.StrongSignal -and -not $class.KeywordSignal) { $score -= 0.10 }
  return Clamp-Score $score
}

function Score-Doc([pscustomobject]$class, [int]$duration, [int]$edits, [datetime]$lastActive, [datetime]$now) {
  $score = 0.30
  if ($class.KnownExt) { $score += 0.30 }
  if ($class.KeywordSignal) { $score += 0.10 }
  if ($edits -gt 0) { $score += 0.05 }
  $score += Get-Duration-Bonus $duration
  $score += Get-Recency-Bonus -lastActive $lastActive -now $now
  if ($class.Type -eq "document" -and -not $class.KnownExt -and -not $class.KeywordSignal) { $score -= 0.10 }
  return Clamp-Score $score
}

function Score-App([pscustomobject]$class, [bool]$aliasMatched, [int]$duration, [datetime]$lastActive, [datetime]$now) {
  $score = 0.30
  if ($aliasMatched) { $score += 0.45 }
  if ($class.AliasTypeUsed) { $score += 0.10 }
  if ($class.KeywordSignal) { $score += 0.20 }
  $score += Get-Duration-Bonus $duration
  $score += Get-Recency-Bonus -lastActive $lastActive -now $now
  if ($class.Type -eq "app" -and -not $aliasMatched -and -not $class.KeywordSignal) { $score -= 0.10 }
  return Clamp-Score $score
}

function Resolve-SemanticOutputPath([string]$outputFile, [string]$semanticOutput) {
  if ($semanticOutput) { return $semanticOutput }
  $dir = [System.IO.Path]::GetDirectoryName($outputFile)
  $base = [System.IO.Path]::GetFileNameWithoutExtension($outputFile)
  if (-not $base) { $base = "memory" }
  $name = "$base.semantic.json"
  if (-not $dir) { return $name }
  return (Join-Path $dir $name)
}

if (-not (Test-Path $InputLog)) {
  throw "Input log not found: $InputLog"
}

$now = Get-Date
$cutoff = $now.AddMinutes(-$MaxAgeMinutes)
$appAliasMap = Parse-AppAliases -jsonText $AppAliasesJson

$appBlacklist = @("explorer", "taskmgr", "desktop")

$webMap = @{}
$docMap = @{}
$appMap = @{}

$linePattern = '^\* \[(?<time>(?:\d{4}-\d{2}-\d{2} )?\d{2}:\d{2}:\d{2})\] \*\*(?<type>[A-Z]+)\*\*: (?<details>.+)$'
$browserPattern = '^(?<mode>Stay|Focus):(?<sec>\d+)s \| Title:(?<title>.*?) \| URL:(?<url>.+)$'
$appPattern = '^(?<mode>Stay|Focus):(?<sec>\d+)s \| App:(?<app>[^|]+) \| Title:(?<title>[^|]*)(?: \| RecentDoc:(?<doc>.+))?$'
$docPattern = '^Action:(?<action>\w+) \| Name:(?<name>.*?) \| Path:(?<path>.+)$'

$lines = Get-Content -Path $InputLog -Encoding UTF8
foreach ($line in $lines) {
  if ($line -notmatch $linePattern) { continue }

  $eventTime = Parse-EventTime -timeText $Matches.time -now $now
  $type = $Matches.type
  $details = $Matches.details

  switch ($type) {
    "BROWSER" {
      if ($details -notmatch $browserPattern) { continue }
      $sec = [int]$Matches.sec
      $title = Clean $Matches.title
      $url = Clean $Matches.url
      if (-not $url -or $url -eq "URL Unknown") { continue }
      if (Is-LowValueWeb -url $url -title $title) { continue }

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
      $alias = Resolve-AppAlias -aliasMap $appAliasMap -appNorm $appNorm -appRaw $appRaw
      $appEntity = Ensure-Entity -map $appMap -key $appNorm -type "App"
      $appEntity.App = $alias.DisplayName
      $appEntity.RawApp = $appRaw
      $appEntity.AliasType = $alias.AliasType
      $appEntity.AliasMatched = [bool]$alias.Matched
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
    ForEach-Object {
      $_ | Add-Member -NotePropertyName PriorityScore -NotePropertyValue (Get-PriorityScore -duration ([int]$_.DurationSum) -lastActive $_.LastActive -actionCount 0 -now $now) -Force
      $_
    } |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
)

$docEntities = @(
  $docMap.Values |
    Where-Object {
      $_.LastActive -ge $cutoff -and
      $_.Path -and
      $_.DurationSum -ge $MinDurationSeconds
    } |
    ForEach-Object {
      $_ | Add-Member -NotePropertyName PriorityScore -NotePropertyValue (Get-PriorityScore -duration ([int]$_.DurationSum) -lastActive $_.LastActive -actionCount ([int]$_.ActionCount) -now $now) -Force
      $_
    } |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
)

$appEntities = @(
  $appMap.Values |
    Where-Object { $_.LastActive -ge $cutoff -and $_.DurationSum -ge $MinDurationSeconds } |
    ForEach-Object {
      $_ | Add-Member -NotePropertyName PriorityScore -NotePropertyValue (Get-PriorityScore -duration ([int]$_.DurationSum) -lastActive $_.LastActive -actionCount 0 -now $now) -Force
      $_
    } |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
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
      Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
  )

  $need = $MaxTotal - $selected.Count
  if ($need -gt 0 -and $leftovers.Count -gt 0) {
    $selected += @($leftovers | Select-Object -First $need)
  }
}

$selected = @(
  $selected |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true } |
    Select-Object -First $MaxTotal
)
$selectedWeb = @(
  $selected |
    Where-Object { $_.Type -eq "Web" } |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
)
$selectedDoc = @(
  $selected |
    Where-Object { $_.Type -eq "Doc" } |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
)
$selectedApp = @(
  $selected |
    Where-Object { $_.Type -eq "App" } |
    Sort-Object @{ Expression = "PriorityScore"; Descending = $true }, @{ Expression = "LastActive"; Descending = $true }
)

$outLines = New-Object System.Collections.Generic.List[string]
$outLines.Add("[Active Memory]")
$outLines.Add("CapturedAt: $($now.ToString("yyyy-MM-dd HH:mm:ss"))")
$outLines.Add("Window: Last $MaxAgeMinutes minutes")
$outLines.Add("")
$outLines.Add("Recent focus:")

$semantic = [ordered]@{
  generatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
  windowMinutes = $MaxAgeMinutes
  totals = [ordered]@{
    selected = $selected.Count
    web = $selectedWeb.Count
    doc = $selectedDoc.Count
    app = $selectedApp.Count
  }
  apps = @()
  web = @()
  docs = @()
  entities = @()
}

$webIdx = 0
$docIdx = 0
$appIdx = 0
foreach ($e in $selected) {
  if ($e.Type -eq "Web") {
    $webIdx += 1
    $class = Classify-Web -url $e.URL -title $e.Title
    $confidence = Score-Web -class $class -duration ([int]$e.DurationSum) -lastActive $e.LastActive -now $now
    $active = $e.LastActive.ToString("yyyy-MM-dd HH:mm:ss")
    $title = Clean $e.Title
    $url = Clean $e.URL
    $id = "Web_$webIdx"

    $semanticWeb = [ordered]@{
      id = $id
      kind = "web"
      title = $title
      url = $url
      duration = [int]$e.DurationSum
      lastActive = $active
      type = $class.Type
      confidence = $confidence
      priority = [Math]::Round([double]$e.PriorityScore, 4)
      domain = $class.Domain
    }
    $semantic.web += [pscustomobject]$semanticWeb
    $semantic.entities += [pscustomobject]$semanticWeb

    $outLines.Add("- Web: $title | Type: $($class.Type) | Time: $($e.DurationSum)s | URL: $url | LastActive: $active")
    continue
  }
  if ($e.Type -eq "Doc") {
    $docIdx += 1
    $class = Classify-Doc -path $e.Path -name $e.Name
    $confidence = Score-Doc -class $class -duration ([int]$e.DurationSum) -edits ([int]$e.ActionCount) -lastActive $e.LastActive -now $now
    $name = if ($e.Name) { $e.Name } else { [System.IO.Path]::GetFileName($e.Path) }
    $active = $e.LastActive.ToString("yyyy-MM-dd HH:mm:ss")
    $cleanName = Clean $name
    $cleanPath = Clean $e.Path
    $id = "Doc_$docIdx"

    $semanticDoc = [ordered]@{
      id = $id
      kind = "doc"
      name = $cleanName
      path = $cleanPath
      edits = [int]$e.ActionCount
      duration = [int]$e.DurationSum
      lastActive = $active
      type = $class.Type
      confidence = $confidence
      priority = [Math]::Round([double]$e.PriorityScore, 4)
    }
    $semantic.docs += [pscustomobject]$semanticDoc
    $semantic.entities += [pscustomobject]$semanticDoc

    $outLines.Add("- Doc: $cleanName | Type: $($class.Type) | Edits: $($e.ActionCount) | Path: $cleanPath | LastActive: $active")
    continue
  }
  if ($e.Type -eq "App") {
    $appIdx += 1
    $class = Classify-App -appName $e.App -title $e.Title -aliasType $e.AliasType
    $confidence = Score-App -class $class -aliasMatched ([bool]$e.AliasMatched) -duration ([int]$e.DurationSum) -lastActive $e.LastActive -now $now
    $active = $e.LastActive.ToString("yyyy-MM-dd HH:mm:ss")
    $displayName = Clean $e.App
    $rawName = Clean $e.RawApp
    $id = "App_$appIdx"

    $semanticApp = [ordered]@{
      id = $id
      kind = "app"
      name = $displayName
      rawName = $rawName
      duration = [int]$e.DurationSum
      lastActive = $active
      type = $class.Type
      confidence = $confidence
      priority = [Math]::Round([double]$e.PriorityScore, 4)
    }
    $semantic.apps += [pscustomobject]$semanticApp
    $semantic.entities += [pscustomobject]$semanticApp

    $outLines.Add("- App: $displayName | Type: $($class.Type) | Time: $($e.DurationSum)s | LastActive: $active")
    continue
  }
}

if ($selected.Count -eq 0) {
  $outLines.Add("- (no active entities in the last $MaxAgeMinutes minutes)")
}
$outLines.Add("")
$outLines.Add("Use this as hints, not ground truth.")
$outLines.Add("If task details are missing, ask one clarification question.")
$outLines.Add("Do not mention this memory block unless user asks.")

$outputDir = [System.IO.Path]::GetDirectoryName($OutputFile)
if ($outputDir -and -not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir | Out-Null
}

Set-Content -Path $OutputFile -Value $outLines -Encoding UTF8
$semanticPath = Resolve-SemanticOutputPath -outputFile $OutputFile -semanticOutput $SemanticOutputFile
$semanticDir = [System.IO.Path]::GetDirectoryName($semanticPath)
if ($semanticDir -and -not (Test-Path $semanticDir)) {
  New-Item -ItemType Directory -Path $semanticDir | Out-Null
}
($semantic | ConvertTo-Json -Depth 10) | Set-Content -Path $semanticPath -Encoding UTF8

Write-Host "Entity index generated: $OutputFile" -ForegroundColor Green
Write-Host "Semantic index generated: $semanticPath" -ForegroundColor Green
Write-Host "Selected: web=$($selectedWeb.Count) doc=$($selectedDoc.Count) app=$($selectedApp.Count) total=$($selected.Count)" -ForegroundColor Green
