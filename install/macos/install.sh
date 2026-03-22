#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${PWD}"
INSTALL_ROOT="${HOME}/.activity2context"
NO_AUTOSTART=0
NO_START_NOW=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --no-autostart)
      NO_AUTOSTART=1
      shift
      ;;
    --no-start-now)
      NO_START_NOW=1
      shift
      ;;
    *)
      echo "Unknown arg: $1"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_SRC="${REPO_ROOT}/runtime"
INTEGRATIONS_SRC="${REPO_ROOT}/integrations"

if [[ ! -d "${RUNTIME_SRC}" ]]; then
  echo "Runtime folder not found: ${RUNTIME_SRC}"
  exit 1
fi

mkdir -p "${INSTALL_ROOT}" "${INSTALL_ROOT}/data" "${INSTALL_ROOT}/run" "${INSTALL_ROOT}/runtime"
cp -R "${RUNTIME_SRC}/." "${INSTALL_ROOT}/runtime/"
if [[ -d "${INTEGRATIONS_SRC}" ]]; then
  mkdir -p "${INSTALL_ROOT}/integrations"
  cp -R "${INTEGRATIONS_SRC}/." "${INSTALL_ROOT}/integrations/"
fi

CONFIG_PATH="${INSTALL_ROOT}/config.json"
if [[ ! -f "${CONFIG_PATH}" ]]; then
  python3 - <<PY
import json
cfg = {
  "workspace": r"${WORKSPACE}",
  "behaviorLog": r"${WORKSPACE}/.openclaw/activity2context_behavior.md",
  "entitiesLog": r"${WORKSPACE}/activity2context/memory.md",
  "observer": {
    "pollSeconds": 2,
    "browserThreshold": 5,
    "browserUpdateInterval": 10,
    "appThreshold": 5,
    "appUpdateInterval": 10,
    "maxBehaviorLines": 5000
  },
  "indexer": {
    "intervalSeconds": 60,
    "minDurationSeconds": 10,
    "maxAgeMinutes": 60,
    "maxTotal": 10,
    "maxWeb": 3,
    "maxDoc": 4,
    "maxApp": 3
  }
}
with open(r"${CONFIG_PATH}", "w", encoding="utf-8") as f:
  json.dump(cfg, f, ensure_ascii=False, indent=2)
  f.write("\n")
PY
fi

LAUNCHER="${INSTALL_ROOT}/activity2context"
cat > "${LAUNCHER}" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_ROOT="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-status}"
python3 "${INSTALL_ROOT}/runtime/macos/activity2contextctl.py" --command "${CMD}" --install-root "${INSTALL_ROOT}"
SH
chmod +x "${LAUNCHER}"

PLIST_PATH="${HOME}/Library/LaunchAgents/io.activity2context.runtime.plist"
if [[ "${NO_AUTOSTART}" -eq 0 ]]; then
  mkdir -p "${HOME}/Library/LaunchAgents"
  cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.activity2context.runtime</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>${INSTALL_ROOT}/runtime/macos/activity2contextctl.py</string>
    <string>--command</string>
    <string>start</string>
    <string>--install-root</string>
    <string>${INSTALL_ROOT}</string>
    <string>--config-path</string>
    <string>${CONFIG_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${INSTALL_ROOT}/run/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${INSTALL_ROOT}/run/launchd.err.log</string>
</dict>
</plist>
PLIST
  launchctl unload "${PLIST_PATH}" >/dev/null 2>&1 || true
  launchctl load "${PLIST_PATH}" >/dev/null 2>&1 || true
else
  launchctl unload "${PLIST_PATH}" >/dev/null 2>&1 || true
  rm -f "${PLIST_PATH}"
fi

if [[ "${NO_START_NOW}" -eq 0 ]]; then
  python3 "${INSTALL_ROOT}/runtime/macos/activity2contextctl.py" \
    --command start \
    --install-root "${INSTALL_ROOT}" \
    --config-path "${CONFIG_PATH}" >/dev/null || true
fi

echo "Activity2Context installed."
echo "Install root: ${INSTALL_ROOT}"
echo "Config: ${CONFIG_PATH}"
echo
echo "Run commands:"
echo "  ${INSTALL_ROOT}/activity2context status"
echo "  ${INSTALL_ROOT}/activity2context start"
echo "  ${INSTALL_ROOT}/activity2context stop"
echo "  ${INSTALL_ROOT}/activity2context index"
