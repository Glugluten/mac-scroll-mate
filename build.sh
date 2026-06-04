#!/bin/zsh
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="${BASE_DIR}/.build/module-cache"
SIGNING_IDENTIFIER="com.glugluten.macscrollmate"
BINARY_TARGET="${BASE_DIR}/Mac Scroll Mate"

mkdir -p "${MODULE_CACHE}"

swiftc \
  -module-cache-path "${MODULE_CACHE}" \
  -F "${SDK_PATH}/System/Library/PrivateFrameworks" \
  -framework PreferencePanesSupport \
  "${BASE_DIR}/MacScrollMate.swift" \
  -o "${BINARY_TARGET}"

codesign --force --sign - --identifier "${SIGNING_IDENTIFIER}" "${BINARY_TARGET}" >/dev/null 2>&1 || true

echo "Built ${BINARY_TARGET}"
