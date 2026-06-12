import unittest

from src.traffic_light_hook import derive_status


class DeriveStatusTests(unittest.TestCase):
    def test_session_start_sets_idle(self) -> None:
        status = derive_status(
            {
                "hook_event_name": "SessionStart",
                "session_id": "session-1",
                "source": "startup",
            }
        )

        self.assertEqual(status["color"], "green")
        self.assertEqual(status["label"], "Idle")

    def test_permission_request_sets_paused_error_state(self) -> None:
        status = derive_status(
            {
                "hook_event_name": "PermissionRequest",
                "session_id": "session-1",
                "tool_name": "Bash",
            }
        )

        self.assertEqual(status["color"], "blue")
        self.assertEqual(status["label"], "Waiting for approval")

    def test_stop_sets_completed(self) -> None:
        status = derive_status(
            {
                "hook_event_name": "Stop",
                "session_id": "session-1",
                "last_assistant_message": "Implemented the requested change.",
            }
        )

        self.assertEqual(status["color"], "green")
        self.assertEqual(status["label"], "Task complete")

    def test_failed_bash_result_sets_error(self) -> None:
        status = derive_status(
            {
                "hook_event_name": "PostToolUse",
                "session_id": "session-1",
                "tool_name": "Bash",
                "tool_response": {
                    "exit_code": 1,
                    "stderr": "fatal: something failed",
                },
            }
        )

        self.assertEqual(status["color"], "red")
        self.assertEqual(status["label"], "Error")

    def test_successful_tool_run_keeps_in_progress(self) -> None:
        status = derive_status(
            {
                "hook_event_name": "PostToolUse",
                "session_id": "session-1",
                "tool_name": "Bash",
                "tool_response": {
                    "exit_code": 0,
                    "stdout": "ok",
                },
            }
        )

        self.assertEqual(status["color"], "yellow")
        self.assertEqual(status["label"], "Task in progress")

    def test_user_prompt_submit_sets_in_progress(self) -> None:
        status = derive_status(
            {
                "hook_event_name": "UserPromptSubmit",
                "session_id": "session-1",
                "prompt": "do work",
            }
        )

        self.assertEqual(status["color"], "yellow")
        self.assertEqual(status["label"], "Task in progress")


if __name__ == "__main__":
    unittest.main()
