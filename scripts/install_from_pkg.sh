#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-user>"
  exit 1
fi

TARGET_USER="$1"
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | awk '{print $2}')

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOKS_TEMPLATE="$REPO_ROOT/hooks/global-hooks.json"
HOOKS_TARGET="$TARGET_HOME/.codex/hooks.json"
LAUNCH_AGENT_TEMPLATE="$REPO_ROOT/assets/com.scott.codex-task-light.monitor.plist"
LAUNCH_AGENT_TARGET="$TARGET_HOME/Library/LaunchAgents/com.scott.codex-task-light.monitor.plist"
APP_PATH="$REPO_ROOT/.runtime/CodexTrafficLight.app"
LAUNCH_AGENT_LABEL="com.scott.codex-task-light.monitor"

mkdir -p "$REPO_ROOT/.runtime"
mkdir -p "$(dirname "$HOOKS_TARGET")"
mkdir -p "$(dirname "$LAUNCH_AGENT_TARGET")"

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
PY

python3 - "$REPO_ROOT" "$LAUNCH_AGENT_TEMPLATE" "$LAUNCH_AGENT_TARGET" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
template = Path(sys.argv[2])
target = Path(sys.argv[3])

content = template.read_text(encoding="utf-8")
content = content.replace("__CODEX_TASK_LIGHT_ROOT__", str(repo))
target.write_text(content, encoding="utf-8")
PY

chown "$TARGET_USER":staff "$HOOKS_TARGET"
chown "$TARGET_USER":staff "$LAUNCH_AGENT_TARGET"

launchctl bootout "gui/$TARGET_UID" "$LAUNCH_AGENT_TARGET" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$TARGET_UID" "$LAUNCH_AGENT_TARGET"
launchctl kickstart -k "gui/$TARGET_UID/$LAUNCH_AGENT_LABEL"

pkill -x CodexTrafficLight >/dev/null 2>&1 || true
sudo -u "$TARGET_USER" /usr/bin/open "$APP_PATH"
