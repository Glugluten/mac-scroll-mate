#!/bin/zsh
set -euo pipefail

LABEL="com.glugluten.macscrollmate.agent"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${HOME}/Library/Application Support/Mac Scroll Mate"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
BINARY_SOURCE="${BASE_DIR}/Mac Scroll Mate"
APP_BUNDLE="${APP_DIR}/Mac Scroll Mate.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_EXECUTABLE="${APP_MACOS}/Mac Scroll Mate"
APP_INFO_PLIST="${APP_CONTENTS}/Info.plist"
CONFIG_SOURCE="${BASE_DIR}/mouse-names.txt"
CONFIG_TARGET="${APP_DIR}/mouse-names.txt"

"${BASE_DIR}/build.sh"

mkdir -p "${HOME}/Library/LaunchAgents"
mkdir -p "${APP_DIR}"
mkdir -p "${APP_MACOS}"
cp "${BINARY_SOURCE}" "${APP_EXECUTABLE}"
chmod +x "${APP_EXECUTABLE}"
cat > "${APP_INFO_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Mac Scroll Mate</string>

  <key>CFBundleIdentifier</key>
  <string>com.glugluten.macscrollmate</string>

  <key>CFBundleName</key>
  <string>Mac Scroll Mate</string>

  <key>CFBundleDisplayName</key>
  <string>Mac Scroll Mate</string>

  <key>CFBundlePackageType</key>
  <string>APPL</string>

  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>

  <key>CFBundleVersion</key>
  <string>1</string>

  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
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
    <string>/usr/bin/open</string>
    <string>-gj</string>
    <string>${APP_BUNDLE}</string>
  </array>

  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>com.glugluten.macscrollmate</string>
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

pkill -x "Mac Scroll Mate" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "${PLIST_TARGET}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_TARGET}"
launchctl enable "gui/$(id -u)/${LABEL}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "Installed ${LABEL}"
echo "If the mouse wheel is not reversed, allow Mac Scroll Mate in System Settings > Privacy & Security > Accessibility and Input Monitoring."
