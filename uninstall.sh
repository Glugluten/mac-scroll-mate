#!/bin/zsh
set -euo pipefail

LABEL="com.glugluten.macscrollmate.agent"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
APP_DIR="${HOME}/Library/Application Support/Mac Scroll Mate"

launchctl bootout "gui/$(id -u)" "${PLIST_TARGET}" 2>/dev/null || true
pkill -x "Mac Scroll Mate" 2>/dev/null || true
rm -f "${PLIST_TARGET}"
rm -rf "${APP_DIR}"

echo "Uninstalled ${LABEL}"
