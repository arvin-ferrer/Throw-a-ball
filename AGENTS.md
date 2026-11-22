# Ball Brawl: Boss Eggs — Shared Agent Rules (`AGENTS.md`)

**Canonical Design Spec:** [GameIdea_Evolved_GDD.md](./GameIdea_Evolved_GDD.md) (`v1.1`)  
**Team Onboarding Guide:** [TEAM_SETUP.md](./TEAM_SETUP.md) (Windows, macOS & Linux)  
**Game Project Root:** `./game/` (Rojo + Rokit + Strict Luau + Lune)  
**3D Asset Root:** `./game/assets/blender/` (Blender 5.x + `mcp-for-blender`)

## 1. Multi-Model Specialist Routing

| Role | Primary Agent / CLI | Owns |
| :--- | :--- | :--- |
| **Tech Director & Visual QA** | **Gemini (`agy`)** | Workflow orchestration (`workflows/`), GDD alignment, multimodal review of Blender renders & Studio captures, UI/UX ergonomics. |
| **Lead Roblox Systems Engineer** | **Claude (`claude`)** | Complex server-authoritative Luau (`ArenaCycleService`, `CombatService`, `DataService`, `EconomyService`, `PetIncomeService`, `PolicyGuardService`), anti-exploit & security audits. |
| **Build, Test & 3D Asset Engineer** | **Codex (`codex`)** | Lune unit tests (`game/tests/*.spec.luau`), data configs (`game/src/shared/Configs/`), headless Blender `bpy` scripts (`game/assets/blender/`), lint/type fixes. |

## 2. Non-Negotiable Architecture & Game Invariants
1. **Strict Luau Everywhere:** Every `.luau` file begins with `--!strict`. Functions stay under 50 lines; extract reusable helpers (DRY & SOLID).
2. **Server Authority:** Never trust client values for Ball Damage, Training Range cooldowns, Cash Pad coin sweeps, `<=12h` offline accrual, `5.0s` Boss Egg claim holds, or PvP damage.
3. **3-Phase Arena Safety:** PvP damage is ONLY valid during `Phase == "PvP_EggScramble"` inside the locked Biome Boss/PvP room. Hub Personal Plots and Open Biome PvE layers are permanently PvP-immune.
4. **Roblox 2026 Compliance (`PolicyService`):** Paid Permanent & Seasonal Shop Eggs MUST check `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` and display exact `100%` odds; restricted regions receive non-random direct bundles. Biome Boss Eggs & 5-Min Overcharged Mutations are NEVER sold for Robux.
5. **Map Safety in Rojo:** Keep `"$ignoreUnknownInstances": true` in `game/default.project.json` so Rojo never deletes Studio-built terrain/meshes.

## 3. Cross-Platform & Team Collaboration Guardrails (Windows / macOS / Linux)
- **Zero Hardcoded User Paths:** Never commit machine-specific paths (`/home/...`, `C:\Users\...`) to `.mcp.json`, configs, or scripts. Use `PATH` lookups (`uvx`, `npx`) or `scripts/*.py` helpers.
- **Cross-Platform Quality Gate:** Before finishing any Luau change, committing, or syncing to Studio, run `python scripts/check.py` (or `./scripts/check.sh`) and confirm 100% pass (StyLua + Selene + Lune unit tests + Rojo build).
- **Cross-Platform Headless Blender:** Always invoke headless Blender scripts via `python scripts/blender_run.py <script.py>` (auto-detects `BLENDER_BIN`, Linux Flatpak `org.blender.Blender`, macOS `Blender.app`, Windows `Program Files`, or `PATH`). On Fedora Linux, never invoke `/usr/bin/blender` directly.
- **Team Create Ownership:** Builders edit Terrain/3D Map layout in Roblox Studio; scripters edit `game/src/**` in Git and sync via Rojo. **Never** run two simultaneous `rojo serve` connections into the same live Team Create place (test on a local `.rbxl` copy or designated dev place, and merge code via Git PRs).
- **Red Before Green:** Write or update a Lune `*.spec.luau` test first, confirm it exercises the behavior, and never mark a task complete without passing `python scripts/check.py`.

## 4. Available Specialist Skills (`.agents/skills/`)
Run `python scripts/setup_team.py` after cloning to install pinned Rokit tools and populate the curated `scenario-roblox-*` and `scenario-blender-*` skills locally. Load the relevant skill before implementing domain-specific Roblox systems or Blender assets.
