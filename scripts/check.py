"""Cross-platform Roblox quality gate (Windows, macOS, Linux).

Runs StyLua format check, Selene lint, Lune unit tests, and Rojo build check.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
GAME_DIR = ROOT_DIR / "game"


def build_tool_env(base_env: dict[str, str] | None = None, home: Path | None = None) -> dict[str, str]:
    """Return environment with Rokit and user-local bin folders prepended to PATH."""
    env = dict(base_env if base_env is not None else os.environ)
    user_home = home if home is not None else Path.home()
    extra_dirs = [user_home / ".rokit" / "bin", user_home / ".local" / "bin"]
    existing = env.get("PATH", "")
    prefix = os.pathsep.join(str(d) for d in extra_dirs if d.exists())
    if prefix:
        env["PATH"] = f"{prefix}{os.pathsep}{existing}" if existing else prefix
    return env


def resolve_tool(name: str, env: dict[str, str]) -> str:
    """Resolve an executable from PATH or raise a clear installation hint."""
    found = shutil.which(name, path=env.get("PATH"))
    if not found:
        raise FileNotFoundError(
            f"Required tool '{name}' not found on PATH. Run `python scripts/setup_team.py` "
            f"or `cd game && rokit install` first."
        )
    return found


def run_step(cmd: list[str], cwd: Path, env: dict[str, str]) -> None:
    """Execute one gate command and raise RuntimeError with exit code on failure."""
    proc = subprocess.run(cmd, cwd=str(cwd), env=env, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"Gate step failed ({proc.returncode}): {' '.join(cmd)}")


def run_all_gates(game_dir: Path = GAME_DIR) -> None:
    """Execute all 4 Roblox verification gates in strict order."""
    env = build_tool_env()
    stylua = resolve_tool("stylua", env)
    selene = resolve_tool("selene", env)
    lune = resolve_tool("lune", env)
    rojo = resolve_tool("rojo", env)

    print("[1/4] StyLua formatting check...")
    run_step([stylua, "--check", "src", "tests"], game_dir, env)

    print("[2/4] Selene lint check...")
    run_step([selene, "src"], game_dir, env)

    print("[3/4] Lune unit tests...")
    specs = sorted((game_dir / "tests").glob("*.spec.luau"))
    if not specs:
        raise RuntimeError(f"No *.spec.luau test files found in {game_dir / 'tests'}")
    for spec in specs:
        rel = spec.relative_to(game_dir)
        print(f"  -> lune run {rel}")
        run_step([lune, "run", str(rel)], game_dir, env)

    print("[4/4] Rojo build check...")
    with tempfile.TemporaryDirectory(prefix="ball_brawl_check_") as tmp_dir:
        out_file = Path(tmp_dir) / "ball_brawl_check.rbxlx"
        run_step([rojo, "build", "default.project.json", "--output", str(out_file)], game_dir, env)
    print("ALL GATES PASSED.")


def main() -> int:
    try:
        run_all_gates()
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"CHECK GATE ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
