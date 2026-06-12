#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


PLUGIN_ROOT = Path(os.environ.get("PLUGIN_ROOT", Path(__file__).resolve().parent.parent))
PLUGIN_DATA = Path(os.environ.get("PLUGIN_DATA", PLUGIN_ROOT / ".runtime"))
SRC_DIR = PLUGIN_ROOT / "src"

if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from traffic_light_hook import derive_status  # noqa: E402


def _state_path() -> Path:
    return PLUGIN_DATA / "state.json"


def _app_path() -> Path:
    return PLUGIN_DATA / "CodexTrafficLight.app"


def _is_running() -> bool:
    for process_name in ("CodexTrafficLight",):
        result = subprocess.run(
            ["/usr/bin/pgrep", "-x", process_name],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return True
    return False


def _launch_app_if_available() -> None:
    app_path = _app_path()
    if _is_running() or not app_path.exists():
        return

    subprocess.Popen(
        ["/usr/bin/open", "-a", str(app_path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> int:
    payload = json.load(sys.stdin)
    status = derive_status(payload)

    PLUGIN_DATA.mkdir(parents=True, exist_ok=True)
    state_path = _state_path()
    temp_path = state_path.with_suffix(".tmp")
    temp_path.write_text(json.dumps(status, ensure_ascii=True, indent=2), encoding="utf-8")
    temp_path.replace(state_path)

    _launch_app_if_available()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
