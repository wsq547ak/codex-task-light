from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def _base_status(payload: dict[str, Any], color: str, label: str, detail: str) -> dict[str, Any]:
    return {
        "session_id": payload.get("session_id"),
        "event": payload.get("hook_event_name"),
        "color": color,
        "label": label,
        "detail": detail,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def _tool_failed(tool_response: Any) -> bool:
    if isinstance(tool_response, dict):
        exit_code = tool_response.get("exit_code")
        if isinstance(exit_code, int) and exit_code != 0:
            return True

        for key in ("error", "stderr", "message"):
            value = tool_response.get(key)
            if isinstance(value, str) and value.strip():
                lowered = value.lower()
                if "error" in lowered or "failed" in lowered or "fatal" in lowered:
                    return True

    if isinstance(tool_response, str):
        lowered = tool_response.lower()
        return "exit code: 0" not in lowered and any(
            token in lowered for token in ("error", "failed", "fatal", "permission denied")
        )

    return False


def derive_status(payload: dict[str, Any]) -> dict[str, Any]:
    event = payload.get("hook_event_name")

    if event == "SessionStart":
        return _base_status(payload, "green", "Idle", "Codex is ready")

    if event in {"UserPromptSubmit", "PreToolUse", "SubagentStart"}:
        return _base_status(payload, "yellow", "Task in progress", event)

    if event == "PermissionRequest":
        return _base_status(payload, "blue", "Waiting for approval", "Codex is paused for permission")

    if event == "PostToolUse":
        if _tool_failed(payload.get("tool_response")):
            return _base_status(payload, "red", "Error", "A tool finished with an error")
        return _base_status(payload, "yellow", "Task in progress", "Tool finished, Codex still running")

    if event in {"Stop", "SubagentStop"}:
        return _base_status(payload, "green", "Task complete", "Codex finished the current turn")

    return _base_status(payload, "yellow", "Task in progress", "Unhandled event")
