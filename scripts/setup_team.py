"""One-command cross-platform team onboarding bootstrapper (Windows, macOS, Linux).

Installs Rokit Roblox tools, syncs curated scenario-labs Roblox & Blender skills into
.agents/skills/ and .claude/skills/, and configures local MCP client/plugin hooks.
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
GAME_DIR = ROOT_DIR / "game"
SCENARIO_REPO_URL = "https://github.com/scenario-labs/skills.git"

ROBLOX_SKILLS = (
    "scenario-roblox-animation",
    "scenario-roblox-architecture",
    "scenario-roblox-assets",
    "scenario-roblox-data",
    "scenario-roblox-environment",
    "scenario-roblox-expert",
    "scenario-roblox-gameplay",
    "scenario-roblox-luau",
    "scenario-roblox-monetization",
    "scenario-roblox-networking",
    "scenario-roblox-performance",
    "scenario-roblox-tooling",
    "scenario-roblox-ui",
    "scenario-roblox-vfx-audio",
)

BLENDER_SKILLS = (
    "scenario-blender-expert",
    "scenario-blender-blockout",
    "scenario-blender-hard-surface",
    "scenario-blender-sculpting",
    "scenario-blender-retopology",
    "scenario-blender-uv-baking",
    "scenario-blender-texturing-shading",
    "scenario-blender-rigging",
    "scenario-blender-animation",
    "scenario-blender-export",
    "scenario-blender-lighting-rendering",
)


def _sync_dir(src: Path, dst: Path, prefer_copy: bool) -> None:
    """Install a single skill folder via copy (Windows-safe) or symlink (Unix)."""
    if dst.is_symlink() or dst.is_file():
        dst.unlink()
    elif dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if prefer_copy:
        shutil.copytree(src, dst)
    else:
        dst.symlink_to(src.resolve())


def sync_curated_skills(
    skills_repo: Path,
    workspace_root: Path = ROOT_DIR,
    prefer_copy: bool | None = None,
) -> int:
    """Populate .agents/skills/ and .claude/skills/ with curated Roblox + Blender skills."""
    use_copy = (platform.system() == "Windows") if prefer_copy is None else prefer_copy
    agents_dir = workspace_root / ".agents" / "skills"
    claude_dir = workspace_root / ".claude" / "skills"
    agents_dir.mkdir(parents=True, exist_ok=True)
    claude_dir.mkdir(parents=True, exist_ok=True)

    installed = 0
    custom_skill = agents_dir / "ball-brawl-pipeline"
    if custom_skill.exists():
        _sync_dir(custom_skill, claude_dir / "ball-brawl-pipeline", prefer_copy=use_copy)

    pairs: list[tuple[Path, str]] = [
        (skills_repo / "skills" / "game-engines" / "roblox" / name, name) for name in ROBLOX_SKILLS
    ] + [
        (skills_repo / "skills" / "dcc" / "blender" / name, name) for name in BLENDER_SKILLS
    ]
    for src, name in pairs:
        if not src.exists():
            continue
        _sync_dir(src, agents_dir / name, prefer_copy=use_copy)
        _sync_dir(src, claude_dir / name, prefer_copy=use_copy)
        installed += 1
    return installed


def ensure_skills_repo(explicit_path: Path | None) -> Path | None:
    """Find an existing scenario-labs/skills checkout or shallow-clone into user cache."""
    candidates = [p for p in (explicit_path, Path.home() / "skills") if p is not None]
    for candidate in candidates:
        if (candidate / "skills" / "game-engines" / "roblox").exists():
            return candidate
    cache_repo = Path.home() / ".cache" / "ball-brawl" / "scenario-skills"
    if (cache_repo / "skills" / "game-engines" / "roblox").exists():
        return cache_repo
    if not shutil.which("git"):
        print("WARN: git not found; skipping scenario-labs/skills clone.", file=sys.stderr)
        return None
    cache_repo.parent.mkdir(parents=True, exist_ok=True)
    print(f"Cloning scenario-labs/skills (shallow) into {cache_repo}...")
    proc = subprocess.run(
        ["git", "clone", "--depth", "1", SCENARIO_REPO_URL, str(cache_repo)],
        check=False,
    )
    return cache_repo if proc.returncode == 0 else None


def install_rokit_tools(game_dir: Path = GAME_DIR) -> bool:
    """Run `rokit install` inside game/ if rokit is available."""
    env = dict(os.environ)
    rokit_bin = Path.home() / ".rokit" / "bin"
    if rokit_bin.exists():
        env["PATH"] = f"{rokit_bin}{os.pathsep}{env.get('PATH', '')}"
    rokit = shutil.which("rokit", path=env.get("PATH"))
    if not rokit:
        print("WARN: 'rokit' not installed. Install from https://github.com/rojo-rbx/rokit")
        return False
    print("Installing pinned Roblox toolchain via rokit...")
    proc = subprocess.run([rokit, "install", "--no-trust-check"], cwd=str(game_dir), env=env, check=False)
    return proc.returncode == 0


def install_mcp_plugins() -> None:
    """Install Blender MCP addon and print Studio MCP plugin guidance for the current OS."""
    uvx = shutil.which("uvx")
    if uvx:
        print("Installing Blender MCP addon via `uvx mcp-for-blender install-addon`...")
        subprocess.run([uvx, "mcp-for-blender", "install-addon"], check=False)
    else:
        print("WARN: 'uvx' not found. Install uv from https://docs.astral.sh/uv/ for Blender MCP.")

    if platform.system() in {"Windows", "Darwin"} and shutil.which("npx"):
        print("TIP: Run `npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin` once to drop the Studio plugin.")
    elif platform.system() == "Linux":
        print("TIP (Linux/Vinegar): Copy MCPPlugin.rbxmx into Vinegar's Wine AppData/Local/Roblox/Plugins folder.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Bootstrap Ball Brawl: Boss Eggs dev environment.")
    parser.add_argument("--skills-repo", type=Path, default=None, help="Path to local scenario-labs/skills clone.")
    parser.add_argument("--copy-skills", action="store_true", help="Copy skills instead of symlinking.")
    parser.add_argument("--skip-rokit", action="store_true", help="Skip running rokit install.")
    parser.add_argument("--skip-mcp", action="store_true", help="Skip MCP addon installation hints.")
    args = parser.parse_args(argv)

    repo = ensure_skills_repo(args.skills_repo)
    if repo:
        count = sync_curated_skills(repo, ROOT_DIR, prefer_copy=True if args.copy_skills else None)
        print(f"Synced {count} curated Roblox & Blender skills into .agents/skills/ and .claude/skills/.")
    else:
        print("WARN: Could not locate or clone scenario-labs/skills; continuing with local project skills.")

    if not args.skip_rokit:
        install_rokit_tools(GAME_DIR)
    if not args.skip_mcp:
        install_mcp_plugins()

    print("Setup complete. Verify anytime with: python scripts/check.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
