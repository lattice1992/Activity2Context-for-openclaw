# OpenClaw Integration (Primary)

`Activity2Context` is designed as an always-on runtime. No skill file is required.

## Recommended integration model

1. Keep runtime processes always running:
- observer writes `activity2context_behavior.md`
- indexer writes `activity2context/memory.md`
- indexer also writes `activity2context/memory.semantic.json`

2. Inject text memory into prompt as Active Memory:
- read `activity2context/memory.md` before each agent turn
- prepend a short block such as:

```text
[Active Memory]
<content of activity2context/memory.md>
```

3. Use structured memory for tools or routing (optional):
- read `activity2context/memory.semantic.json` for machine-friendly entities
- keep it out of the direct prompt unless needed
4. Keep integration runtime-only:
- do not rely on skill invocation for core context collection
- inject `activity2context/memory.md` directly via OpenClaw hook

## Recommended file path for OpenClaw

`bootstrap-extra-files` can only inject files inside the workspace, so point
`entitiesLog` to a workspace path.

Example:
- `entitiesLog: <workspace>/activity2context/memory.md`
- Hook path: `activity2context/memory.md`

Then configure OpenClaw:

```bash
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

## Why this split

- Always-on runtime gives consistent context regardless of agent behavior
- Skill routing is heuristic; runtime collection should not depend on it
- Token usage stays low because only entity summary is injected, not raw logs
