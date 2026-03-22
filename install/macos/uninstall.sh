#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${HOME}/.activity2context"
KEEP_DATA=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --keep-data)
      KEEP_DATA=1
      shift
      ;;
    *)
      echo "Unknown arg: $1"
      exit 1
      ;;
  esac
done

CTL="${INSTALL_ROOT}/runtime/macos/activity2contextctl.py"
if [[ -f "${CTL}" ]]; then
  python3 "${CTL}" --command stop --install-root "${INSTALL_ROOT}" >/dev/null 2>&1 || true
fi

PLIST_PATH="${HOME}/Library/LaunchAgents/io.activity2context.runtime.plist"
launchctl unload "${PLIST_PATH}" >/dev/null 2>&1 || true
rm -f "${PLIST_PATH}"

if [[ ! -d "${INSTALL_ROOT}" ]]; then
  echo "Nothing to uninstall at ${INSTALL_ROOT}"
  exit 0
fi

if [[ "${KEEP_DATA}" -eq 1 ]]; then
  rm -rf "${INSTALL_ROOT}/runtime" "${INSTALL_ROOT}/integrations"
  rm -f "${INSTALL_ROOT}/activity2context"
  echo "Activity2Context runtime removed; data retained in ${INSTALL_ROOT}/data"
else
  rm -rf "${INSTALL_ROOT}"
  echo "Activity2Context fully uninstalled: ${INSTALL_ROOT}"
fi
