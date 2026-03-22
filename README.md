# Activity2Context (for OpenClaw)

OpenClaw-focused, always-on local runtime that converts fragmented activity logs into compact context entities.
100% Local & Private: All activity logging happens entirely on your local machine. No data is sent to the cloud. It's designed to be read locally by your local or API-driven agent.

## Positioning

`Activity2Context` is infrastructure, not just a skill:
- Runtime layer (always-on): collect and aggregate activity
- Adapter layer (optional): expose maintenance actions to an agent skill

This keeps context stable and low-token even when skill routing is imperfect.

## Scope

- Primary target: OpenClaw
- Integration model: injected workspace memory file via OpenClaw bootstrap hooks
- Status: optimized for OpenClaw workflows first, other agent frameworks second

## Workshop Mode (No Git Required, Windows)

If your team is non-technical, use this path:

1. Download ZIP from GitHub (`Code` -> `Download ZIP`)
2. Unzip to a local folder
3. Double-click:
- `easy-install-windows.bat` (install + start)
- `easy-status-windows.bat` (health check)
- `easy-open-memory-windows.bat` (open generated memory)

Chinese step-by-step guide:
- `WORKSHOP_QUICKSTART_CN.md`
- `INSTALL_GITHUB_ONLY_CN.md` (GitHub-only path)

## What it produces

- `activity2context_behavior.md` (raw-ish behavioral stream)
- `activity2context_entities.md` (filtered entity index for prompt injection)
- OpenClaw-friendly default from installers: `<workspace>/activity2context/memory.md`

Entity buckets:
- Web: key = URL
- Doc: key = Path
- App: key = App Name

## Quick Start (Windows)

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "D:\AIproject"
```

After install, control it with:

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd status
$env:USERPROFILE\.activity2context\activity2context.cmd start
$env:USERPROFILE\.activity2context\activity2context.cmd stop
$env:USERPROFILE\.activity2context\activity2context.cmd index
```

## Quick Start (macOS)

From repo root:

```bash
bash ./install/macos/install.sh --workspace "$PWD"
```

After install, control it with:

```bash
~/.activity2context/activity2context status
~/.activity2context/activity2context start
~/.activity2context/activity2context stop
~/.activity2context/activity2context index
```

macOS permissions required:
- Accessibility (for foreground app/window detection via System Events)
- Automation for browser apps (Chrome/Edge/Brave/Safari URL reads)
- Python 3 (`/usr/bin/python3`) available

## Install flow for other users

1. Clone repository
2. Run installer:
- Windows: `install/windows/install.ps1`
- macOS: `install/macos/install.sh`
3. Installer creates:
- runtime files under `~/.activity2context`
- `config.json`
- auto-start entry unless disabled:
  - Windows: Startup cmd
  - macOS: LaunchAgent `io.activity2context.runtime`
4. Runtime starts now (unless `-NoStartNow`) and on next login (unless `-NoAutoStart`)
  - Windows flags: `-NoStartNow`, `-NoAutoStart`
  - macOS flags: `--no-start-now`, `--no-autostart`

## Config

Config file:
- `~/.activity2context/config.json`

Template:
- `config/activity2context.example.json`
- `config/activity2context.macos.example.json`

Key controls:
- observer thresholds and poll interval
- raw behavior cap: `observer.maxBehaviorLines` (default `5000`, trimmed once at startup)
- indexer interval and entity limits
- workspace and output paths

## OpenClaw integration

See:
- `integrations/openclaw/README.md`

Recommended pattern:
- inject `activity2context_entities.md` into system prompt as Active Memory
- keep skill optional for operational commands

OpenClaw-specific note:
- set `entitiesLog` to a workspace file (for example `./activity2context/memory.md`)
- configure hook path to `activity2context/memory.md`

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\uninstall.ps1
```

```bash
bash ./install/macos/uninstall.sh
```

Keep data but remove runtime:

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\uninstall.ps1 -KeepData
```

```bash
bash ./install/macos/uninstall.sh --keep-data
```
