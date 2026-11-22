# Ball Brawl: Boss Eggs

A cross-platform Roblox game repository pairing a **Training & Pet-Income Tycoon** with a high-stakes **3-Phase Arena (`PvE → Boss → Uncapped PvP Egg Scramble`)**, powered by Rojo, Rokit, strict Luau, Lune unit testing, Blender 5.x, and a multi-model AI development workflow (`Gemini`, `Claude`, `Codex`).

---

## Start Here

- **Canonical Game Design Document:** [docs/GameIdea_Evolved_GDD.md](docs/GameIdea_Evolved_GDD.md) | [PDF (9 pages)](docs/GameIdea_Evolved_GDD.pdf)
- **Team Onboarding (Windows / macOS / Linux):** [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md)
- **Roblox Game Codebase Guide:** [game/README.md](game/README.md)
- **Shared AI Agent Rules:** [AGENTS.md](AGENTS.md) · [GEMINI.md](GEMINI.md) · [CLAUDE.md](CLAUDE.md)
- **Market Research & Validation Vault:** [research/README.md](research/README.md) · [Visual Summary](research/reports/Research_Results_Visual_Summary.md)

---

## Quick Start (All Operating Systems)

```bash
# 1. Bootstrap pinned Rokit tools, curated Roblox/Blender skills, and MCP addons
python scripts/setup_team.py

# 2. Run all 4 automated Roblox quality gates (StyLua, Selene, Lune, Rojo build)
python scripts/check.py

# 3. Start Rojo live sync into Roblox Studio
cd game && rojo serve

# 4. Run a headless Blender 5.x asset script (auto-detects OS / Flatpak Blender)
python scripts/blender_run.py game/assets/blender/starter_egg_template.py
```

---

## Repository Structure

```text
.
├── AGENTS.md / CLAUDE.md / GEMINI.md   # Shared & specialist multi-model agent rules
├── .mcp.json                           # Portable MCP config (robloxstudio + blender)
├── .agents/skills/                     # Custom project skill + local synced scenario-* skills
├── .github/                            # CI quality gate workflow & PR checklist template
├── docs/                               # Canonical GDD (MD + PDF), TEAM_SETUP.md & archive/
├── game/                               # Roblox Rojo + Rokit project & Blender 3D assets
│   ├── default.project.json            # Rojo tree ($ignoreUnknownInstances: true)
│   ├── rokit.toml                      # Pinned rojo, wally, lune, selene, stylua, luau-lsp
│   ├── src/{shared,server,client}/     # Strict Luau source modules
│   ├── tests/                          # Lune *.spec.luau unit tests
│   └── assets/{blender,imports,exports,renders,audio,ui}/
├── scripts/                            # Cross-platform Python runners (setup, check, blender, cli)
├── workflows/                          # Antigravity multi-model orchestration scripts
└── research/                           # Late-2026 Roblox market research, data, charts & reports
```

---

## Testing & Verification Commands

```bash
python scripts/check.py                                  # StyLua + Selene + Lune + Rojo build
python -m unittest discover -s scripts/tests -v          # Cross-platform tooling unit tests
python -m unittest discover -s research/tests -v         # Research data, charts & PDF tests
```
