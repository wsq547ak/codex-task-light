#!/bin/zsh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
HOOKS_TEMPLATE="$REPO_ROOT/hooks/global-hooks.json"
HOOKS_TARGET="$HOME/.codex/hooks.json"
LAUNCH_AGENT_TEMPLATE="$REPO_ROOT/assets/com.scott.codex-task-light.monitor.plist"
LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/com.scott.codex-task-light.monitor.plist"
APP_PATH="$REPO_ROOT/.runtime/CodexTrafficLight.app"
LAUNCH_AGENT_LABEL="com.scott.codex-task-light.monitor"

echo "==> Building CX menu bar app"
"$REPO_ROOT/scripts/build_menubar_app.sh"

echo "==> Installing Codex hooks to $HOOKS_TARGET"
mkdir -p "$(dirname "$HOOKS_TARGET")"

python3 - "$REPO_ROOT" "$HOOKS_TEMPLATE" "$HOOKS_TARGET" <<'PY'
from pathlib import Path
import json
import sys

repo = Path(sys.argv[1])
template = Path(sys.argv[2])
target = Path(sys.argv[3])

data = json.loads(template.read_text(encoding="utf-8"))
hook_command = f'/usr/bin/python3 {repo / "scripts" / "hook_entry.py"}'

for event_groups in data["hooks"].values():
    for group in event_groups:
        for hook in group["hooks"]:
            hook["command"] = hook_command

target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Wrote {target}")
PY

echo "==> Installing LaunchAgent to $LAUNCH_AGENT_TARGET"
mkdir -p "$(dirname "$LAUNCH_AGENT_TARGET")"

python3 - "$REPO_ROOT" "$LAUNCH_AGENT_TEMPLATE" "$LAUNCH_AGENT_TARGET" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
template = Path(sys.argv[2])
target = Path(sys.argv[3])

content = template.read_text(encoding="utf-8")
content = content.replace("__CODEX_TASK_LIGHT_ROOT__", str(repo))
target.write_text(content, encoding="utf-8")
print(f"Wrote {target}")
PY

echo "==> Reloading LaunchAgent"
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_TARGET" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_TARGET"
launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL"

echo "==> Restarting CX"
killall CodexTrafficLight >/dev/null 2>&1 || true
open "$APP_PATH"

cat <<EOF

Installation complete.

Next step in Codex:
1. Run /hooks
2. Trust every hook entry that points to:
   $REPO_ROOT/scripts/hook_entry.py

After trust is granted, CX will update colors from Codex task events.
EOF
