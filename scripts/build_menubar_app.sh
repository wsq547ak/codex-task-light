#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PLUGIN_DATA=${PLUGIN_DATA:-"$PLUGIN_ROOT/.runtime"}
APP_NAME="CodexTrafficLight"
APP_BUNDLE="$PLUGIN_DATA/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
MODULE_CACHE_DIR="$PLUGIN_ROOT/.build/module-cache"

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$MODULE_CACHE_DIR"

/usr/bin/swiftc \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework Cocoa \
  "$PLUGIN_ROOT/assets/CodexTrafficLight.swift" \
  -o "$APP_MACOS/$APP_NAME"

cp "$PLUGIN_ROOT/assets/Info.plist" "$APP_CONTENTS/Info.plist"

echo "Built menu bar app at: $APP_BUNDLE"
