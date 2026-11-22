"""Cross-platform multi-model CLI dispatcher for Claude Code and Codex CLI."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]


def build_dispatch_command(target: str, prompt: str) -> list[str]:
    """Resolve target CLI binary and construct non-interactive invocation."""
    if target not in {"claude", "codex"}:
        raise ValueError(f"Unsupported target '{target}' (expected 'claude' or 'codex')")
    binary = shutil.which(target)
    if not binary:
        raise FileNotFoundError(
            f"CLI '{target}' not found on PATH. Install it or run the task directly in your active agent."
        )
    if target == "claude":
        return [binary, "-p", prompt]
    return [binary, "exec", prompt]


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) < 2:
        print("Usage: python scripts/dispatch_cli.py <claude|codex> <prompt>", file=sys.stderr)
        return 1
    target, prompt = args[0], " ".join(args[1:])
    try:
        cmd = build_dispatch_command(target, prompt)
    except (ValueError, FileNotFoundError) as exc:
        print(f"DISPATCH ERROR: {exc}", file=sys.stderr)
        return 1
    return subprocess.run(cmd, cwd=str(ROOT_DIR), check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
