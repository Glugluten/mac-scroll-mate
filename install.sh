#!/bin/zsh
set -euo pipefail

LABEL="com.naturalscrollauto.agent"
LEGACY_LABEL="com.codex.natural-scroll-auto"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${HOME}/Library/Application Support/NaturalScrollAuto"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LEGACY_PLIST_TARGET="${HOME}/Library/LaunchAgents/${LEGACY_LABEL}.plist"
BINARY_SOURCE="${BASE_DIR}/NaturalScrollAuto"
BINARY_TARGET="${APP_DIR}/NaturalScrollAuto"
CONFIG_SOURCE="${BASE_DIR}/mouse-names.txt"
CONFIG_TARGET="${APP_DIR}/mouse-names.txt"

if [[ ! -x "${BINARY_SOURCE}" ]]; then
  "${BASE_DIR}/build.sh"
fi

mkdir -p "${HOME}/Library/LaunchAgents"
mkdir -p "${APP_DIR}"
cp "${BINARY_SOURCE}" "${BINARY_TARGET}"
chmod +x "${BINARY_TARGET}"
if [[ ! -f "${CONFIG_TARGET}" ]]; then
  cp "${CONFIG_SOURCE}" "${CONFIG_TARGET}"
fi
cat > "${PLIST_TARGET}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${BINARY_TARGET}</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/tmp/${LABEL}.out.log</string>

  <key>StandardErrorPath</key>
  <string>/tmp/${LABEL}.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "${LEGACY_PLIST_TARGET}" 2>/dev/null || true
rm -f "${LEGACY_PLIST_TARGET}"

launchctl bootout "gui/$(id -u)" "${PLIST_TARGET}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_TARGET}"
launchctl enable "gui/$(id -u)/${LABEL}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "Installed ${LABEL}"
