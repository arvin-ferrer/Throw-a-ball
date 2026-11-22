"""Hand a task to a live Gemini (agy) or Codex session running in a kitty window.

Types a one-line prompt into the agent's window via kitty remote control, then waits
for the agent to write its result file. Needs in kitty.conf (Linux/macOS kitty only):
    allow_remote_control socket-only
    listen_on unix:/tmp/kitty-<name>

Usage:
    python scripts/agent_bridge.py <gemini|codex> <step> "<task text>" [--timeout 1800]
The agent is told to write .agent_loop/<step>.md and end it with a line `STATUS: DONE`.
"""

from __future__ import annotations

import argparse
import glob
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
LOOP_DIR = ROOT_DIR / ".agent_loop"
AGENT_PROCS = {"gemini": "agy", "codex": "codex"}
DONE_MARKER = "STATUS: DONE"


def locate(proc: str) -> tuple[str, int]:
    """Search every kitty instance's socket (kitty appends -<pid>) for the agent window."""
    socks = glob.glob("/tmp/kitty-*")
    if not socks:
        raise RuntimeError("No kitty socket in /tmp/kitty-*. Enable listen_on and open a new kitty.")
    for sock in socks:
        ls = subprocess.run(["kitty", "@", "--to", f"unix:{sock}", "ls"], capture_output=True, text=True)
        if ls.returncode != 0:
            continue  # stale socket from a closed kitty
        try:
            return f"unix:{sock}", find_window(json.loads(ls.stdout), proc)
        except RuntimeError:
            continue
    raise RuntimeError(f"No kitty window is running '{proc}'. Start it in a kitty opened after the config change.")


def find_window(windows: list[dict], proc: str) -> int:
    """Return the id of the kitty window whose foreground process is `proc`."""
    for os_win in windows:
        for tab in os_win["tabs"]:
            for win in tab["windows"]:
                for fg in win.get("foreground_processes", []):
                    if fg.get("cmdline") and Path(fg["cmdline"][0]).name == proc:
                        return int(win["id"])
    raise RuntimeError(f"No kitty window is running '{proc}'. Open it in kitty first.")


def build_prompt(step: str, task: str) -> str:
    """One line only: a newline would submit the prompt early in the agent's TUI."""
    out = f".agent_loop/{step}.md"
    return (
        f"{' '.join(task.split())} -- Follow AGENTS.md. Do NOT git commit. When finished, write your "
        f"result/summary to {out} and make its last line exactly: {DONE_MARKER}"
    )


def send(agent: str, step: str, task: str) -> Path:
    """Clear any stale result, type the prompt into the agent window and press Enter."""
    sock, win_id = locate(AGENT_PROCS[agent])
    LOOP_DIR.mkdir(exist_ok=True)
    result = LOOP_DIR / f"{step}.md"
    result.unlink(missing_ok=True)
    match = f"id:{win_id}"
    # Esc first: dismisses startup popups (e.g. agy's announcements) that would eat the prompt.
    subprocess.run(["kitty", "@", "--to", sock, "send-key", "--match", match, "escape"], check=True)
    time.sleep(0.3)
    subprocess.run(["kitty", "@", "--to", sock, "send-text", "--match", match, build_prompt(step, task)], check=True)
    time.sleep(0.5)  # let the TUI finish the paste before Enter
    subprocess.run(["kitty", "@", "--to", sock, "send-key", "--match", match, "enter"], check=True)
    return result


def wait_for(result: Path, timeout: float, poll: float = 5.0) -> str:
    """Block until the result file ends with the done marker; return its text."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if result.exists():
            text = result.read_text(encoding="utf-8")
            if text.rstrip().endswith(DONE_MARKER):
                return text
        time.sleep(poll)
    raise TimeoutError(f"No finished {result.name} after {timeout:.0f}s")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Send a task to a live agent window and wait.")
    parser.add_argument("agent", choices=sorted(AGENT_PROCS))
    parser.add_argument("step", help="Result name, e.g. 01-plan -> .agent_loop/01-plan.md")
    parser.add_argument("task")
    parser.add_argument("--timeout", type=float, default=1800)
    args = parser.parse_args(argv)
    try:
        print(wait_for(send(args.agent, args.step, args.task), args.timeout))
        return 0
    except (RuntimeError, TimeoutError, subprocess.CalledProcessError) as exc:
        print(f"BRIDGE ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
