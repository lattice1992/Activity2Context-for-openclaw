# Activity2Context for OpenClaw

Chinese version: `README.zh-CN.md`

Imagine an agent that can "see what you see and track what you do."

When you want fast execution, you only provide the goal.
You do not need to repeatedly feed background context every turn.

## What problem does it solve?

- Context gaps: you just edited files and read pages, but the agent does not know.
- Repetitive briefing: you keep re-explaining what you were doing.
- Token waste: raw behavior logs are noisy and expensive if sent directly to models.

## How it works

Activity2Context is a Runtime Hook, not a Skill.

Pipeline:

1. Capture: continuously record local activity (browser, document, app).
2. Aggregate: compress raw streams into structured entities.
3. Inject: before each chat turn, inject `activity2context/memory.md` into the OpenClaw system prompt.

## What is captured (current)

- Browser: page title, URL, focus duration, last active time.
- Document: file path, edit count, last active time.
- App: app name, window title, focus duration, last active time.

Outputs:

- Raw stream: `<workspace>/.openclaw/activity2context_behavior.md`
- Injected memory: `<workspace>/activity2context/memory.md`

## Common concerns

### 1) Will token cost increase a lot?

Usually no. Only aggregated `memory.md` is injected, not full raw logs.
Entity count is capped and ranked by recency/activity.

### 2) Is it safe for privacy?

By default, data is generated and stored locally.
However, if you use cloud models, injected `memory.md` content is sent with prompts to your model provider.
For sensitive environments, prefer local models or narrower capture scope.

### 3) Will it hurt performance?

The runtime is lightweight (polling + periodic aggregation).
Raw logs are capped and trimmed, preventing unbounded I/O growth.

### 4) Will the logs grow indefinitely??

- Raw log cap: `observer.maxBehaviorLines` (default `5000`).
- Auto-trim on startup to keep only the latest N lines.
- Injected file is aggregated memory, not full raw logs.

## Quick Start (Windows)

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "$PWD"
```

If your OpenClaw workspace is different from the current folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "C:\path\to\your\workspace"
```

Control commands:

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

Control commands:

```bash
~/.activity2context/activity2context status
~/.activity2context/activity2context start
~/.activity2context/activity2context stop
~/.activity2context/activity2context index
```

Required macOS permissions:

- Accessibility (foreground app/window detection)
- Automation (read Chrome/Edge/Brave/Safari URL)
- Python 3 (`/usr/bin/python3`)

## OpenClaw Integration (core)

You only need `memory.md` injection. No Skill file is required.

```bash
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

More details: `integrations/openclaw/README.md`


## Configuration

Config file:

- `~/.activity2context/config.json`

Templates:

- `config/activity2context.example.json`
- `config/activity2context.macos.example.json`

Key parameters:

- `observer.pollSeconds`
- `observer.browserThreshold`
- `observer.browserUpdateInterval`
- `observer.appThreshold`
- `observer.appUpdateInterval`
- `observer.maxBehaviorLines` (default 5000)
- `indexer.intervalSeconds`
- `indexer.minDurationSeconds`
- `indexer.maxAgeMinutes`
- `indexer.maxTotal`
- `indexer.maxWeb`
- `indexer.maxDoc`
- `indexer.maxApp`

## Uninstall

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\uninstall.ps1
```

macOS:

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
