#!/bin/zsh
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="${BASE_DIR}/.build/module-cache"

mkdir -p "${MODULE_CACHE}"

swiftc \
  -module-cache-path "${MODULE_CACHE}" \
  -F "${SDK_PATH}/System/Library/PrivateFrameworks" \
  -framework PreferencePanesSupport \
  "${BASE_DIR}/NaturalScrollAuto.swift" \
  -o "${BASE_DIR}/NaturalScrollAuto"

echo "Built ${BASE_DIR}/NaturalScrollAuto"
