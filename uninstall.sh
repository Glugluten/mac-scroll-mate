#!/bin/zsh
set -euo pipefail

LABEL="com.naturalscrollauto.agent"
LEGACY_LABEL="com.codex.natural-scroll-auto"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LEGACY_PLIST_TARGET="${HOME}/Library/LaunchAgents/${LEGACY_LABEL}.plist"
APP_DIR="${HOME}/Library/Application Support/NaturalScrollAuto"

launchctl bootout "gui/$(id -u)" "${PLIST_TARGET}" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "${LEGACY_PLIST_TARGET}" 2>/dev/null || true
rm -f "${PLIST_TARGET}"
rm -f "${LEGACY_PLIST_TARGET}"
rm -f "${APP_DIR}/natural-scroll-auto.sh"
rm -f "${APP_DIR}/NaturalScrollAuto"
rm -f "${APP_DIR}/mouse-names.txt"
rmdir "${APP_DIR}" 2>/dev/null || true

echo "Uninstalled ${LABEL}"
