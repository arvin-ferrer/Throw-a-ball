"""Cross-platform headless Blender runner (Windows, macOS, Linux/Flatpak)."""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


def _find_windows_blender(program_files: Path) -> Path | None:
    """Return newest Blender Foundation executable under Program Files, if present."""
    base = program_files / "Blender Foundation"
    if not base.exists():
        return None
    candidates = sorted(base.glob("Blender */blender.exe"), reverse=True)
    return candidates[0] if candidates else None


def _has_flatpak_blender() -> bool:
    """Return True when Flatpak org.blender.Blender is installed on Linux."""
    if not shutil.which("flatpak"):
        return False
    proc = subprocess.run(
        ["flatpak", "info", "org.blender.Blender"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode == 0


def resolve_blender_command(
    system: str | None = None,
    env: dict[str, str] | None = None,
    flatpak_available: bool | None = None,
) -> list[str]:
    """Determine the safest Blender executable command for the host OS."""
    os_name = system or platform.system()
    environ = env if env is not None else os.environ

    override = environ.get("BLENDER_BIN", "").strip()
    if override:
        return [override]

    if os_name == "Linux":
        has_fp = _has_flatpak_blender() if flatpak_available is None else flatpak_available
        if has_fp:
            return ["flatpak", "run", "--filesystem=home", "org.blender.Blender"]

    if os_name == "Darwin":
        mac_bin = Path("/Applications/Blender.app/Contents/MacOS/Blender")
        if mac_bin.exists():
            return [str(mac_bin)]

    if os_name == "Windows":
        pf = Path(environ.get("ProgramFiles", r"C:\Program Files"))
        win_bin = _find_windows_blender(pf)
        if win_bin:
            return [str(win_bin)]

    on_path = shutil.which("blender")
    if on_path:
        return [on_path]

    raise FileNotFoundError(
        "Blender not found. Install Blender 5.x (Flatpak on Linux, blender.org on Windows/macOS) "
        "or set BLENDER_BIN=/path/to/blender."
    )


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print("Usage: python scripts/blender_run.py <script.py> [extra args...]", file=sys.stderr)
        return 1
    script_path = Path(args[0]).resolve()
    extra = args[1:]
    try:
        base_cmd = resolve_blender_command()
    except FileNotFoundError as exc:
        print(f"BLENDER ERROR: {exc}", file=sys.stderr)
        return 1

    cmd = [
        *base_cmd,
        "--background",
        "--factory-startup",
        "--python-exit-code",
        "1",
        "--python",
        str(script_path),
        "--",
        *extra,
    ]
    return subprocess.run(cmd, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
