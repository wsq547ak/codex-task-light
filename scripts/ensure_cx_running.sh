#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
APP_PATH="$PLUGIN_ROOT/.runtime/CodexTrafficLight.app"

if ! /usr/bin/pgrep -x "Codex" >/dev/null 2>&1; then
  exit 0
fi

if /usr/bin/pgrep -x "CodexTrafficLight" >/dev/null 2>&1; then
  exit 0
fi

if [[ -d "$APP_PATH" ]]; then
  /usr/bin/open "$APP_PATH"
fi
