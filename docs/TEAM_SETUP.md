# Team Collaboration & Machine Setup Guide (`TEAM_SETUP.md`)

This repository is configured to work identically across **Windows**, **macOS**, and **Linux** (including Fedora + Flatpak Vinegar/Blender) with pinned Roblox tooling, cross-platform Python runners, and shared AI agent rules & MCP servers.

---

## 1. Prerequisites (Install Once Per Machine)

| Tool | Purpose | Install |
| :--- | :--- | :--- |
| **Git & Python 3.10+** | Version control & cross-platform runners | OS package manager / [python.org](https://www.python.org/) |
| **Node.js 20+ (`npx`)** | Roblox Studio MCP (`@chrrxs/robloxstudio-mcp`) | [nodejs.org](https://nodejs.org/) |
| **`uv` (`uvx`)** | Blender MCP (`mcp-for-blender`) | **macOS/Linux:** `curl -LsSf https://astral.sh/uv/install.sh \| sh`<br>**Windows (PowerShell):** `irm https://astral.sh/uv/install.ps1 \| iex` |
| **Rokit** | Pins exact `rojo`, `wally`, `lune`, `selene`, `stylua`, `luau-lsp` versions | **macOS/Linux:** `curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh \| bash`<br>**Windows (PowerShell):** `irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 \| iex` |
| **Roblox Studio** | Live sync & playtesting | Native on Windows/macOS; Flatpak `org.vinegarhq.Vinegar` on Linux |
| **Blender 5.x** | 3D Pet/Egg/Boss modeling & headless `.glb` export | Native on Windows/macOS ([blender.org](https://www.blender.org/)); Flatpak `org.blender.Blender` on Linux |

*(Optional AI CLIs: install any subset of Antigravity `agy`, Claude Code `claude`, or OpenAI `codex` — all three read the same project rules and MCP servers!)*

---

## 2. One-Command Repository Bootstrap

After cloning the repo, run:

```bash
python scripts/setup_team.py
```

*(On macOS/Linux you may use `python3 scripts/setup_team.py`.)*

What this does automatically:
1. Installs the exact pinned Roblox toolchain from [game/rokit.toml](../game/rokit.toml) (`rojo`, `wally`, `lune`, `selene`, `stylua`, `luau-lsp`).
2. Clones/syncs the curated `26` Roblox & Blender expert skills from `scenario-labs/skills` into `.agents/skills/` and `.claude/skills/` (using Windows-safe directory copies on Windows and symlinks on macOS/Linux; these third-party folders are gitignored so teammates never get broken symlinks!).
3. Installs the **`mcp-for-blender`** addon into your Blender addons folder (`uvx mcp-for-blender install-addon`).

Verify your setup immediately:

```bash
python scripts/check.py
```

Expected output: `ALL GATES PASSED.` (StyLua + Selene + Lune unit tests + Rojo build).

---

## 3. Connect Your MCP Servers & Studio/Blender Plugins

### Project-Level MCP Config
[.mcp.json](../.mcp.json) is checked into Git with zero machine-specific paths (`npx` and `uvx` resolved from `PATH`), so **Claude Code** picks up `robloxstudio` and `blender` automatically.

For **Antigravity** (`~/.gemini/config/mcp_config.json`), add:
```json
{
  "mcpServers": {
    "robloxstudio": { "command": "npx", "args": ["-y", "@chrrxs/robloxstudio-mcp@latest"] },
    "blender": { "command": "uvx", "args": ["mcp-for-blender"] }
  }
}
```

For **Codex CLI** (`~/.codex/config.toml`), add:
```toml
[mcp_servers.robloxstudio]
command = "npx"
args = ["-y", "@chrrxs/robloxstudio-mcp@latest"]

[mcp_servers.blender]
command = "uvx"
args = ["mcp-for-blender"]
```

### One-Time Plugin Activation
- **Roblox Studio (Windows & macOS):**
  1. Run once: `npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin`
  2. Install the official **Rojo** plugin in Studio.
  3. In Studio: **Game Settings → Security → Allow HTTP Requests = ON**, then toggle the **MCP** button in the Plugins toolbar.
- **Roblox Studio (Linux / Flatpak Vinegar):**
  - Copy `MCPPlugin.rbxmx` from `@chrrxs/robloxstudio-mcp` into `~/.var/app/org.vinegarhq.Vinegar/data/vinegar/prefixes/studio/drive_c/users/$USER/AppData/Local/Roblox/Plugins/`, then enable HTTP Requests & click the MCP toolbar button.
- **Blender 5.x (All OSes):**
  - Open Blender → **Edit → Preferences → Add-ons** → enable **Interface: MCP for Blender** → press `N` in 3D Viewport → **MCP for Blender → Connect to MCP server**.

---

## 4. Daily Team Collaboration Workflow (Preventing Conflicts)

| Role | Where You Work | Sync & Merge Rule |
| :--- | :--- | :--- |
| **Scripters / Engineers** | Git branch → `game/src/**` & `game/tests/**` | Test locally via `cd game && rojo serve` against a local place copy. Run `python scripts/check.py` before opening a PR. **Never** connect two teammates' `rojo serve` sessions to the same live Team Create place at once! |
| **3D / Environment Builders** | Roblox Studio (Map/Terrain) & `game/assets/blender/` | Because [game/default.project.json](../game/default.project.json) enforces `"$ignoreUnknownInstances": true`, Rojo preserves Studio-built Terrain/Parts/Meshes safely. Export Blender assets via `python scripts/blender_run.py <script.py>`. |
| **Reviewers / Visual QA** | PR diff + `game/assets/renders/*.png` | Verify `python scripts/check.py` passes, check `AGENTS.md` security invariants (`PolicyService`, server authority, PvP phase guard), and review render previews before merging to `main`. |
