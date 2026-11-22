"""Unit tests for cross-platform scripts (check.py, blender_run.py, setup_team.py, .mcp.json)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT_DIR / "scripts"))

import blender_run
import check
import dispatch_cli
import setup_team


class TestCrossPlatformScripts(unittest.TestCase):
    """Verify OS-independent path resolution, skill syncing, and portable MCP config."""

    def test_mcp_json_has_no_machine_specific_paths(self) -> None:
        mcp_path = ROOT_DIR / ".mcp.json"
        data = json.loads(mcp_path.read_text(encoding="utf-8"))
        servers = data.get("mcpServers", {})
        self.assertIn("robloxstudio", servers)
        self.assertIn("blender", servers)
        for name, cfg in servers.items():
            cmd = cfg["command"]
            self.assertNotIn("/home/", cmd, f"{name} contains hardcoded Linux home path")
            self.assertNotIn("C:\\", cmd, f"{name} contains hardcoded Windows path")

    def test_blender_run_resolution_across_platforms(self) -> None:
        self.assertEqual(
            blender_run.resolve_blender_command(system="Linux", env={"BLENDER_BIN": "/custom/blender"}),
            ["/custom/blender"],
        )
        self.assertEqual(
            blender_run.resolve_blender_command(system="Linux", env={}, flatpak_available=True),
            ["flatpak", "run", "--filesystem=home", "org.blender.Blender"],
        )

    def test_windows_blender_discovery_picks_newest_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pf = Path(tmp)
            old_bin = pf / "Blender Foundation" / "Blender 4.2" / "blender.exe"
            new_bin = pf / "Blender Foundation" / "Blender 5.3" / "blender.exe"
            old_bin.parent.mkdir(parents=True)
            new_bin.parent.mkdir(parents=True)
            old_bin.write_text("", encoding="utf-8")
            new_bin.write_text("", encoding="utf-8")
            self.assertEqual(blender_run._find_windows_blender(pf), new_bin)

    def test_check_build_tool_env_prepends_rokit_bin(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_home = Path(tmp)
            rokit_bin = fake_home / ".rokit" / "bin"
            rokit_bin.mkdir(parents=True)
            env = check.build_tool_env(base_env={"PATH": "/usr/bin"}, home=fake_home)
            self.assertTrue(env["PATH"].startswith(str(rokit_bin)))

    def test_dispatch_cli_rejects_unknown_target(self) -> None:
        with self.assertRaises(ValueError):
            dispatch_cli.build_dispatch_command("unknown-agent", "hello")

    def test_setup_team_sync_curated_skills_copy_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_repo = root / "skills_repo"
            r_skill = fake_repo / "skills" / "game-engines" / "roblox" / "scenario-roblox-expert"
            b_skill = fake_repo / "skills" / "dcc" / "blender" / "scenario-blender-expert"
            r_skill.mkdir(parents=True)
            b_skill.mkdir(parents=True)
            (r_skill / "SKILL.md").write_text("# Roblox", encoding="utf-8")
            (b_skill / "SKILL.md").write_text("# Blender", encoding="utf-8")

            ws = root / "workspace"
            custom = ws / ".agents" / "skills" / "ball-brawl-pipeline"
            custom.mkdir(parents=True)
            (custom / "SKILL.md").write_text("# Custom", encoding="utf-8")

            count = setup_team.sync_curated_skills(fake_repo, workspace_root=ws, prefer_copy=True)
            self.assertEqual(count, 2)
            self.assertTrue((ws / ".agents" / "skills" / "scenario-roblox-expert" / "SKILL.md").exists())
            self.assertTrue((ws / ".claude" / "skills" / "scenario-blender-expert" / "SKILL.md").exists())
            self.assertTrue((ws / ".claude" / "skills" / "ball-brawl-pipeline" / "SKILL.md").exists())
            self.assertFalse((ws / ".agents" / "skills" / "scenario-roblox-expert").is_symlink())


if __name__ == "__main__":
    unittest.main()
