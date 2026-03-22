# Activity2Context Publish Checklist

## 1) Clean local runtime artifacts

- Remove local runtime data before publishing:
  - `run/`
  - `memory.md`
  - `config.local.json`

(`.gitignore` already excludes these by default.)

## 2) Sanity check docs

- `README.md` includes:
  - Windows install/uninstall
  - macOS install/uninstall
  - OpenClaw integration notes
- `integrations/openclaw/README.md` includes hook config commands.

## 3) Verify installers

- Windows:
  - `install/windows/install.ps1`
  - `install/windows/uninstall.ps1`
- macOS:
  - `install/macos/install.sh`
  - `install/macos/uninstall.sh`

## 4) Verify runtime layout

- Windows runtime:
  - `runtime/windows/*`
- macOS runtime:
  - `runtime/macos/*`

## 5) Tag release

- Suggested tag format:
  - `v0.1.0`
- Suggested release title:
  - `Activity2Context v0.1.0 (Windows + macOS)`

## 6) Post-release smoke test

- Fresh machine test:
  1. Install runtime
  2. Start runtime
  3. Confirm behavior log updates
  4. Confirm entities output updates
  5. Confirm OpenClaw injects workspace `activity2context/memory.md`
