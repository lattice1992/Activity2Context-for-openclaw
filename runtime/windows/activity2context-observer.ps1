param(
  [string]$Workspace = (Get-Location).Path,
  [string]$LogFile = "$env:USERPROFILE\.activity2context\data\activity2context_behavior.md",
  [int]$BrowserThreshold = 5,
  [int]$BrowserUpdateInterval = 10,
  [int]$AppThreshold = 5,
  [int]$AppUpdateInterval = 10,
  [int]$PollSeconds = 2
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Win32 {
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", SetLastError=true)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@

$script:State = @{
  CurrentHwnd = [IntPtr]::Zero
  StartTime = Get-Date
  LastProcess = ""
  LastTitle = ""
  LastURL = ""
  LastDocumentPath = ""
  BrowserEntryEmitted = $false
  LastBrowserTick = $null
  AppEntryEmitted = $false
  LastAppTick = $null
}

$script:FileThrottle = @{}
$script:BrowserProcs = @("chrome", "msedge", "brave", "firefox")
$script:IgnoreProcs = @("explorer", "taskmgr", "shellexperiencehost", "searchhost", "idle", "system", "unknown")

function Resolve-BrowserFromTitle([string]$title) {
  if (-not $title) { return $null }
  if ($title -match "(?i) - Google Chrome$") { return "chrome" }
  if ($title -match "(?i) - Microsoft Edge$") { return "msedge" }
  if ($title -match "(?i) - Mozilla Firefox$") { return "firefox" }
  if ($title -match "(?i) - Brave$") { return "brave" }
  return $null
}

function Write-BehaviorLog([string]$Type, [string]$Details) {
  $timestamp = Get-Date -Format "HH:mm:ss"
  $date = Get-Date -Format "yyyy-MM-dd"
  $line = "* [$timestamp] **$Type**: $Details"

  $dir = [System.IO.Path]::GetDirectoryName($LogFile)
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  if (!(Test-Path $LogFile)) { "# Activity2Context Behavior Context - $date`n" | Out-File $LogFile -Encoding UTF8 }

  $line | Add-Content -Path $LogFile -Encoding UTF8
  Write-Host $line -ForegroundColor Cyan
}

function Write-OrUpdate-BrowserLog([string]$Mode, [int]$Seconds, [string]$Title, [string]$URL) {
  if (-not $Title) { $Title = "" }
  if (-not $URL) { $URL = "URL Unknown" }
  $timestamp = Get-Date -Format "HH:mm:ss"
  $date = Get-Date -Format "yyyy-MM-dd"
  $line = "* [$timestamp] **BROWSER**: ${Mode}:$($Seconds)s | Title:$Title | URL:$URL"

  $dir = [System.IO.Path]::GetDirectoryName($LogFile)
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  if (!(Test-Path $LogFile)) { "# Activity2Context Behavior Context - $date`n" | Out-File $LogFile -Encoding UTF8 }

  $lines = Get-Content -Path $LogFile -Encoding UTF8
  $lastBrowserIndex = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match '^\* \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \*\*BROWSER\*\*:') {
      $lastBrowserIndex = $i
      break
    }
  }

  $samePage = $false
  if ($lastBrowserIndex -ge 0) {
    $samePage = ($lines[$lastBrowserIndex] -like "* | Title:$Title | URL:$URL")
  }

  if ($samePage) {
    $lines[$lastBrowserIndex] = $line
    Set-Content -Path $LogFile -Value $lines -Encoding UTF8
  } else {
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
  }

  Write-Host $line -ForegroundColor Cyan
}

function Write-OrUpdate-AppLog([string]$Mode, [int]$Seconds, [string]$App, [string]$Title, [string]$RecentDoc) {
  if (-not $App) { $App = "unknown" }
  if (-not $Title) { $Title = "" }
  $timestamp = Get-Date -Format "HH:mm:ss"
  $date = Get-Date -Format "yyyy-MM-dd"

  $details = "${Mode}:$($Seconds)s | App:$App | Title:$Title"
  if ($RecentDoc) {
    $details = "$details | RecentDoc:$RecentDoc"
  }
  $line = "* [$timestamp] **APP**: $details"

  $dir = [System.IO.Path]::GetDirectoryName($LogFile)
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  if (!(Test-Path $LogFile)) { "# Activity2Context Behavior Context - $date`n" | Out-File $LogFile -Encoding UTF8 }

  $lines = Get-Content -Path $LogFile -Encoding UTF8
  $lastAppIndex = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match '^\* \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \*\*APP\*\*:') {
      $lastAppIndex = $i
      break
    }
  }

  $sameAppWindow = $false
  if ($lastAppIndex -ge 0) {
    $sameAppWindow = ($lines[$lastAppIndex] -like "* | App:$App | Title:$Title*")
  }

  if ($sameAppWindow) {
    $lines[$lastAppIndex] = $line
    Set-Content -Path $LogFile -Value $lines -Encoding UTF8
  } else {
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
  }

  Write-Host $line -ForegroundColor Cyan
}

function Get-URLFromHwnd([IntPtr]$Hwnd, [string]$ProcessName) {
  if ($script:BrowserProcs -notcontains $ProcessName) { return $null }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    if (-not $root) { return "URL Unknown" }

    $addressNames = @(
      "Address and search bar",
      "Search or enter web address"
    )

    foreach ($name in $addressNames) {
      $named = $root.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
          [System.Windows.Automation.AutomationElement]::NameProperty,
          $name
        ))
      )
      if ($named) {
        $value = $null
        if ($named.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$value)) {
          $candidate = $value.Current.Value
          if ($candidate -and ($candidate -match '^https?://' -or $candidate -match '^[a-z0-9.-]+\.[a-z]{2,}')) {
            return $candidate
          }
        }
      }
    }

    $edits = $root.FindAll(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit
      ))
    )

    foreach ($node in $edits) {
      $value = $null
      if ($node.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$value)) {
        $candidate = $value.Current.Value
        if ($candidate -and ($candidate -match '^https?://' -or $candidate -match '^[a-z0-9.-]+\.[a-z]{2,}')) {
          return $candidate
        }
      }
    }
  } catch {}

  return "URL Unknown"
}

function Get-WindowSnapshot([IntPtr]$Hwnd, [string]$ProcessName) {
  $sb = New-Object System.Text.StringBuilder 512
  [void][Win32]::GetWindowText($Hwnd, $sb, $sb.Capacity)
  $title = $sb.ToString()
  $url = Get-URLFromHwnd -Hwnd $Hwnd -ProcessName $ProcessName
  return @{
    Title = $title
    URL = $url
  }
}

function Finalize-CurrentWindow {
  if ($script:State.CurrentHwnd -eq [IntPtr]::Zero) { return }

  $duration = ((Get-Date) - $script:State.StartTime).TotalSeconds
  $proc = $script:State.LastProcess
  $title = $script:State.LastTitle
  $url = $script:State.LastURL

  if ($script:BrowserProcs -contains $proc) {
    if ($duration -ge $BrowserThreshold) {
      Write-OrUpdate-BrowserLog -Mode "Focus" -Seconds ([math]::Round($duration)) -Title $title -URL $url
    }
    return
  }

  if ($script:IgnoreProcs -notcontains $proc -and $duration -ge $AppThreshold) {
    Write-OrUpdate-AppLog -Mode "Focus" -Seconds ([math]::Round($duration)) -App $proc -Title $title -RecentDoc $script:State.LastDocumentPath
  }
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $Workspace
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$createdId = "activity2context.fs.created"
$changedId = "activity2context.fs.changed"
Unregister-Event -SourceIdentifier $createdId -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier $changedId -ErrorAction SilentlyContinue

Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier $createdId | Out-Null
Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier $changedId | Out-Null

function Handle-FileEvent($eventArgs) {
  if (-not $eventArgs) { return }
  $path = $eventArgs.FullPath
  if (-not $path) { return }
  if (Test-Path -PathType Container $path) { return }
  if ($path -match "\\\.openclaw\\|\\\.git\\|\\node_modules\\|\\__pycache__\\") { return }
  if ($path -match "\.tmp$|\.log$|~$") { return }

  $now = Get-Date
  if ($script:FileThrottle.ContainsKey($path)) {
    if (($now - $script:FileThrottle[$path]).TotalSeconds -lt 3) { return }
  }
  $script:FileThrottle[$path] = $now

  $name = $eventArgs.Name
  $action = $eventArgs.ChangeType
  $fullPath = [System.IO.Path]::GetFullPath($path)
  $script:State.LastDocumentPath = $fullPath
  Write-BehaviorLog "DOCUMENT" "Action:$action | Name:$name | Path:$fullPath"
}

$stopFile = Join-Path ([System.IO.Path]::GetDirectoryName($LogFile)) "stop.flag"
Write-Host "Observer started. Monitoring $Workspace" -ForegroundColor Green
Write-BehaviorLog "SYSTEM" "Observer started. Workspace=$Workspace Poll=${PollSeconds}s BrowserFirstLogSeconds=${BrowserThreshold}s BrowserUpdateInterval=${BrowserUpdateInterval}s AppThreshold=${AppThreshold}s AppUpdateInterval=${AppUpdateInterval}s"

while ($true) {
  foreach ($sid in @($createdId, $changedId)) {
    while ($true) {
      $evt = Get-Event -SourceIdentifier $sid -ErrorAction SilentlyContinue | Select-Object -First 1
      if (-not $evt) { break }
      Handle-FileEvent $evt.SourceEventArgs
      Remove-Event -EventIdentifier $evt.EventIdentifier -ErrorAction SilentlyContinue
    }
  }

  if (Test-Path $stopFile) {
    Remove-Item $stopFile -Force | Out-Null
    Write-BehaviorLog "SYSTEM" "Stop flag detected. Exiting."
    break
  }

  $hwnd = [Win32]::GetForegroundWindow()
  if ($hwnd -ne $script:State.CurrentHwnd) {
    Finalize-CurrentWindow

    [uint32]$winPid = 0
    [void][Win32]::GetWindowThreadProcessId($hwnd, [ref]$winPid)
    if ($winPid -le 4) {
      $pname = "unknown"
    } else {
      $proc = Get-Process -Id $winPid -ErrorAction SilentlyContinue
      $pname = if ($proc) { $proc.ProcessName.ToLower() } else { "unknown" }
    }

    if ($pname -eq "unknown") {
      $titleProbe = (Get-WindowSnapshot -Hwnd $hwnd -ProcessName "unknown").Title
      $browserHint = Resolve-BrowserFromTitle $titleProbe
      if ($browserHint) { $pname = $browserHint }
    }

    $snapshot = Get-WindowSnapshot -Hwnd $hwnd -ProcessName $pname

    $script:State.CurrentHwnd = $hwnd
    $script:State.StartTime = Get-Date
    $script:State.LastProcess = $pname
    $script:State.LastTitle = $snapshot.Title
    $script:State.LastURL = $snapshot.URL
    $script:State.BrowserEntryEmitted = $false
    $script:State.LastBrowserTick = $null
    $script:State.AppEntryEmitted = $false
    $script:State.LastAppTick = $null
  } elseif ($script:BrowserProcs -contains $script:State.LastProcess) {
    # Same browser window, but page may have changed (new tab/url/title).
    $snapshot = Get-WindowSnapshot -Hwnd $hwnd -ProcessName $script:State.LastProcess
    $currentTitle = $snapshot.Title
    $currentUrl = $snapshot.URL
    $oldTitle = $script:State.LastTitle
    $oldUrl = $script:State.LastURL

    $urlChanged = $false
    if ($oldUrl -and $oldUrl -ne "URL Unknown" -and $currentUrl -and $currentUrl -ne "URL Unknown" -and $currentUrl -ne $oldUrl) {
      $urlChanged = $true
    }

    $titleChanged = $false
    if ($currentTitle -ne $oldTitle) {
      $titleChanged = $true
    }

    $pageChanged = $urlChanged -or (($oldUrl -eq "URL Unknown" -or -not $oldUrl) -and $titleChanged)
    if ($pageChanged) {
      $duration = ((Get-Date) - $script:State.StartTime).TotalSeconds
      if ($duration -ge $BrowserThreshold) {
        Write-OrUpdate-BrowserLog -Mode "Focus" -Seconds ([math]::Round($duration)) -Title $oldTitle -URL $oldUrl
      }

      $script:State.StartTime = Get-Date
      $script:State.LastTitle = $currentTitle
      $script:State.LastURL = $currentUrl
      $script:State.BrowserEntryEmitted = $false
      $script:State.LastBrowserTick = $null
    } else {
      # Keep URL fresh if it was unknown initially and later becomes available.
      if (($oldUrl -eq "URL Unknown" -or -not $oldUrl) -and $currentUrl -and $currentUrl -ne "URL Unknown") {
        $script:State.LastURL = $currentUrl
      }
      if ((-not $oldTitle) -and $currentTitle) {
        $script:State.LastTitle = $currentTitle
      }
    }
  }

  # Browser stay logging:
  # 1) first line at BrowserThreshold seconds
  # 2) update same page line every BrowserUpdateInterval seconds
  if ($script:BrowserProcs -contains $script:State.LastProcess) {
    $elapsed = ((Get-Date) - $script:State.StartTime).TotalSeconds
    if ($elapsed -ge $BrowserThreshold) {
      if (-not $script:State.BrowserEntryEmitted) {
        Write-OrUpdate-BrowserLog -Mode "Stay" -Seconds ([math]::Round($elapsed)) -Title $script:State.LastTitle -URL $script:State.LastURL
        $script:State.BrowserEntryEmitted = $true
        $script:State.LastBrowserTick = Get-Date
      } else {
        $sinceLast = if ($script:State.LastBrowserTick) { ((Get-Date) - $script:State.LastBrowserTick).TotalSeconds } else { 999999 }
        if ($sinceLast -ge $BrowserUpdateInterval) {
          Write-OrUpdate-BrowserLog -Mode "Stay" -Seconds ([math]::Round($elapsed)) -Title $script:State.LastTitle -URL $script:State.LastURL
          $script:State.LastBrowserTick = Get-Date
        }
      }
    }
  }

  # App stay logging:
  # 1) first line at AppThreshold seconds
  # 2) update same app/title line every AppUpdateInterval seconds
  if ($script:BrowserProcs -notcontains $script:State.LastProcess -and $script:IgnoreProcs -notcontains $script:State.LastProcess) {
    $elapsed = ((Get-Date) - $script:State.StartTime).TotalSeconds
    if ($elapsed -ge $AppThreshold) {
      if (-not $script:State.AppEntryEmitted) {
        Write-OrUpdate-AppLog -Mode "Stay" -Seconds ([math]::Round($elapsed)) -App $script:State.LastProcess -Title $script:State.LastTitle -RecentDoc $script:State.LastDocumentPath
        $script:State.AppEntryEmitted = $true
        $script:State.LastAppTick = Get-Date
      } else {
        $sinceLastApp = if ($script:State.LastAppTick) { ((Get-Date) - $script:State.LastAppTick).TotalSeconds } else { 999999 }
        if ($sinceLastApp -ge $AppUpdateInterval) {
          Write-OrUpdate-AppLog -Mode "Stay" -Seconds ([math]::Round($elapsed)) -App $script:State.LastProcess -Title $script:State.LastTitle -RecentDoc $script:State.LastDocumentPath
          $script:State.LastAppTick = Get-Date
        }
      }
    }
  }

  Start-Sleep -Seconds $PollSeconds
}

Finalize-CurrentWindow
Write-BehaviorLog "SYSTEM" "Observer stopped."
Write-Host "Observer stopped." -ForegroundColor Yellow

Unregister-Event -SourceIdentifier $createdId -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier $changedId -ErrorAction SilentlyContinue
