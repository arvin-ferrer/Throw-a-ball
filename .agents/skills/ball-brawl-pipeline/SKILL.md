---
name: ball-brawl-pipeline
description: >-
  Cross-platform project runbook for developing Ball Brawl: Boss Eggs on Windows,
  macOS, and Linux with Rojo, Rokit, Lune, Roblox Studio MCP, Blender 5.x MCP,
  and multi-model routing across Gemini (agy), Claude (claude), and Codex (codex).
---

# Ball Brawl: Boss Eggs — Cross-Platform Agentic Pipeline Runbook

## 1. Universal Environment Facts (Windows / macOS / Linux)
- **GDD:** `GameIdea_Evolved_GDD.md` (`v1.1`)
- **Team Onboarding:** `TEAM_SETUP.md` (run `python scripts/setup_team.py` once after cloning)
- **Rojo Project:** `game/` (`game/default.project.json`, `game/rokit.toml`)
- **Headless Blender Runner:** `python scripts/blender_run.py <script.py>` (auto-detects `BLENDER_BIN`, Linux Flatpak `org.blender.Blender`, macOS `Blender.app`, Windows `Program Files`, or `PATH`).
- **Quality Gate:** `python scripts/check.py` (StyLua + Selene + Lune unit tests + `rojo build`).
- **Live MCP Servers:** `robloxstudio` (`npx -y @chrrxs/robloxstudio-mcp@latest`) and `blender` (`uvx mcp-for-blender`).

## 2. Standard Feature Loop (Red -> Green -> Studio)
1. **Plan (Gemini / `agy`):** Confirm requirement against `GameIdea_Evolved_GDD.md` and identify target modules (`shared/Configs`, `server/Services`, `client/Controllers`, `tests/`).
2. **Test First (Codex / `codex`):** Add or extend a Lune spec in `game/tests/*.spec.luau` testing pure logic & edge cases.
3. **Implement (Claude / `claude`):** Implement strict Luau (`--!strict`) module under `game/src/` with server-authoritative validation.
4. **Verify Gate:** Run `python scripts/check.py`. Fix every warning/failure before committing or opening a PR.
5. **Sync & Live Verify:** With Roblox Studio open (Rojo connected to your local/dev place + Studio MCP plugin active), verify instance hierarchy and playtest behavior via `robloxstudio` MCP tools. Never point two teammates' `rojo serve` sessions at the same Team Create place simultaneously.

## 3. Blender 3D Asset Loop (Stylized Low-Poly Roblox)
1. Load `scenario-blender-expert` + `scenario-blender-blockout` / `scenario-blender-export` skills.
2. Script asset generation in `game/assets/blender/<asset_name>.py` (Codex) or iterate interactively via `blender` MCP (`uvx mcp-for-blender`).
3. Run `python scripts/blender_run.py game/assets/blender/<asset_name>.py` to export `.glb`/`.fbx` to `game/assets/exports/` and a preview PNG to `game/assets/renders/`.
4. Open the render PNG (Gemini Visual QA) to check silhouette readability on mobile screens, polygon budget (`<2.5k` tris for Pets/Eggs, `<6k` tris for Bosses), and pivot orientation.

## 4. OS-Specific Notes
- **Windows / macOS:** Native Roblox Studio & Blender work directly (`npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin` and `uvx mcp-for-blender install-addon`).
- **Linux (Fedora / Flatpak):** Roblox Studio runs via Flatpak Vinegar (`org.vinegarhq.Vinegar`) with `MCPPlugin.rbxmx` in Vinegar's Wine `AppData/Local/Roblox/Plugins` folder; Blender runs via Flatpak `org.blender.Blender` (never `/usr/bin/blender`).
