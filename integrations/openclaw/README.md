# OpenClaw Integration

`Activity2Context` is designed as an always-on runtime, not only as a skill.

## Recommended integration model

1. Keep runtime processes always running:
- observer writes `activity2context_behavior.md`
- indexer writes `activity2context_entities.md`

2. Inject entities file into prompt as Active Memory:
- read `activity2context_entities.md` before each agent turn
- prepend a short block such as:

```text
[ACTIVE MEMORY]
<content of activity2context_entities.md>
```

3. Keep skill optional:
- use a skill for maintenance tasks only (`status`, `reindex`, `pause`, `resume`)
- do not rely on skill invocation for core context collection

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
- Skill invocation is heuristic; runtime collection should not depend on it
- Token usage stays low because only entity summary is injected, not raw logs
