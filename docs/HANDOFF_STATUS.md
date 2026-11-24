# Ball Brawl: Boss Eggs — Team Handoff & Project Status

**Last Updated:** 2026-11-24 (`main @ ce78a7f` + `chore/19-studio-qa-and-handoff`, PRs `#21`–`#44` merged; synced & saved to Team Create `placeId: 76642126183926` v`73`)

**Canonical Design Spec:** [GameIdea_Evolved_GDD.md](GameIdea_Evolved_GDD.md) (`v1.1`)

**Team Workflow & Contracts:** [TEAM_WORKFLOW_3P.md](TEAM_WORKFLOW_3P.md) · [TEAM_SETUP.md](TEAM_SETUP.md)

This document is the single source of truth for **what is merged and verified on `main`**, **current GitHub issue status (`#1`–`#20`)**, **remaining manual Roblox Studio / Open Cloud / Creator Hub launch steps**, and the **live module architecture**.

---

## 1. Executive Summary — Where the Game Stands Today

- **Server Authority, Economy & Telemetry (`#1`, `#4`, `#5`, `#9`, `#10`, `#14`, `#15`, `#18`): Complete on `main` (P1 Audit Hardened in PRs `#42`–`#44`)**
  All 9 server services (`DataService`, `PolicyGuardService`, `PlotService`, `ArenaCycleService`, `BossAIService`, `CombatService`, `PetIncomeService`, `EconomyService`, `TelemetryService`) are merged on `main` (`ce78a7f`) with `--!strict`, lease-token DataStore session locking with departure retry & `BindToClose` hardening, fail-closed Roblox 2026 `PolicyService` compliance (including owned paid-egg hatch fallback), atomic `ProcessReceipt` handling, locked-room PvP containment with scramble deadline & authored room bounds, homing world sweep, 8-plot capacity + vertical pad alignment, and first-session/offer cohort telemetry (`TelemetryLogic`, PR `#37` & `#44`).
- **Client UI, Combat, Shop & 0–5m Onboarding (`#2`, `#6`, `#7`, `#11`, `#12`, `#16`, `#19`): Merged & Studio QA Verified on `chore/19-studio-qa-and-handoff` (`#19` Ready to Close)**
  Following PRs `#36`, `#38`, `#39`, `#40`, and `#42` (9 joint Pet × Mutation `100.00%` odds disclosure in `ShopCodexGui`), all 6 client controllers (`AnimationController`, `ArenaHUDController`, `BallThrowController`, `HatchVFXController`, `OnboardingGuideController`, `PlotCashController`) and 5 UI modules (`HudGui`, `HudIcons`, `HubModalsGui`, `ShopCodexGui`, `Theme`) are synced (`38/38` SHA-256 parity) into Studio Team Create (`v73`). Live Studio Device Simulator & `PolicyService` QA on `chore/19-studio-qa-and-handoff` resolved 5 mobile/modal layout bugs (`HudGui` `2x2` drawer padding + `HeroStatusDock` vertical clearance + `44px` `AutoAimBtn`; `HubModalsGui` & `ShopCodexGui` `LayoutOrder` sorting, wrapped upgrade text, and `44x44` close button) and passed across `667x375` iPhone 7, `874x402` iPhone 17 Pro, `1376x1032` iPad Pro M5, and PC.
- **3D Assets & Launch Art (`#3`, `#8`, `#13`, `#17`, `#20`): Blender Exports & Launch Art Merged; Open Cloud Upload & Biome 2–3 Studio Art Open**
  All 39 Blender 5.x scripts (`game/assets/blender/`), 35 `.fbx` / 36 `.glb` exports (`game/assets/exports/`), 40 preview/QA renders (`game/assets/renders/`), and 13 Cycles launch UI assets (`game/assets/ui/`: 3 × 16:9 thumbnails, 512×512 game icon, 5 Game Pass icons, and 4 Badge icons) are merged on `main` (PR `#29`, PR `#32`, PR `#36`, PR `#40`). Issues `#13` and `#17` remain open solely for Roblox Open Cloud asset upload (blocked until `~/.config/roblox/opencloud.key` is configured) and interactive Roblox Studio Hub / Biome 2–3 map art finishing.

---

## 2. Complete Issue Status Matrix (`#1`–`#20`)

| # | Phase | Role | Issue | Status | Notes / What Remains |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | P0 | Server | Shared Configs & Typed Remotes | **Closed** | All 6 config modules (`Biome`, `Economy`, `Egg`, `Monetization`, `Pet`, `Trait`) & `Remotes.luau` live on `main`. |
| **2** | P0 | Client | Client Bootstrap & Remote Wrapper | **Closed (PR #21)** | Merged (`PR #21`) and evolved via `PR #33` / `PR #36` into `init.client.luau` + `Controllers/` + `UI/`. |
| **3** | P0 | 3D/Map | Hub Plaza & Meadow Greybox (`BallBrawl_Map_v2`) | **Closed** | `Workspace.BallBrawl_Map_v2` imported in Studio with `26` `CollectionService` tags matching `TEAM_WORKFLOW_3P.md`. |
| **4** | P1 | Server | `ArenaCycleService` (3-Phase FSM, 5s Claim, Storm) | **Closed (PR #23, #43)** | Hardened in `PR #37` & `PR #43` with scramble `phaseEndsAt` deadline, authored room bounds, entrant pre-pruning, and single payout settlement. |
| **5** | P1 | Server | `CombatService` & `BossAIService` (Mossback Golem) | **Closed (PR #24, #43)** | Evolved with ballistic/homing throws + world sweep (`PR #35`, `#36`, `#43`), arena-validated damage (`PR #37`), and KO position capture (`PR #40`). |
| **6** | P1 | Client | `BallThrowController` (Training, Dodge, Aim Assist) | **Closed (PR #22, #43)** | Evolved with PC camera aim (`PR #34`), live bounce rebound (`PR #35`), 60 FPS animations (`PR #36`), cosmetic VFX (`PR #40`), and homing sweep alignment (`PR #43`). |
| **7** | P1 | Client | `ArenaHUDController` (Banner, Opt-In, 5s Ring) | **Closed (PR #24)** | Updated with tweened Overcharged lighting and 44px mobile claim ergonomics (`PR #38`). |
| **8** | P1 | 3D/Map | Meadow 3D Assets (Golem, Mobs, Balls, Boss Egg) | **Closed (PR #29)** | Blender exports/renders merged (`PR #29`, `PR #32`, `PR #36`). Studio `rbxassetid://` binding tracked under `#13` / `#17`. |
| **9** | P2 | Server | `DataService` & `EconomyService` (Persistence, Ascension) | **Closed (PR #25, #44)** | Hardened in `PR #37` & `PR #44` with lease-token locking, departure lease retry/`BindToClose`, Studio-only memory fallback, and finite/overflow ledger guards. |
| **10** | P2 | Server | `PetIncomeService` & `PlotService` (Cash Pads, Offline, Fusion) | **Closed (PR #26, #42, #43)** | Hardened in `PR #37`, `PR #42` (fail-closed policy on paid hatch), `PR #43` (vertical pad + 8-plot capacity), and `PR #40` (themes/rig reuse). |
| **11** | P2 | Client | `PlotCashController`, `HatchVFXController` & Followers | **Closed (PR #30)** | Evolved with `AudioCatalog` chimes, `AnimationController` (`PR #36`), and `SupernovaHatch` beam VFX (`PR #40`). |
| **12** | P2 | Client | Hub Progression UIs (`HubModalsGui`) | **Closed (PR #36)** | Pets (Lv 1–25, Fusion, Traits, Followers, Pedestals), Eggs/Crafting, and Upgrades/Ascension tabs live in `HubModalsGui.luau` (`LayoutOrder`/wrapping fixed in `#19` QA). |
| **13** | P2 | 3D/Map | Hub Plaza Art, Tier 1–3 Plots & Starter/Meadow Pets | **Open (Exports Merged)** | Blender assets merged (`PR #29` / `PR #32`) & 8-plot capacity aligned (`PR #43`). **Remaining:** Open Cloud upload (`~/.config/roblox/opencloud.key`) + Studio Hub/Plot art pass. |
| **14** | P3 | Server | 5-Min Overcharged Scheduler, Biome 2–3 Bosses & Active Perks | **Closed (PR #27)** | Live across `ArenaCycleLogic`, `BossAIService`, `CombatLogic`, and `ArenaHUDController`. |
| **15** | P3 | Server | `PolicyGuardService` & Exactly-Once `ProcessReceipt` | **Closed (PR #28, #42, #44)** | Hardened in `PR #37`, `PR #42` (fail-closed paid hatch), and `PR #44` with policy lookup tokens and durable committed receipt checks. |
| **16** | P3 | Client | Codex UI, Overcharged Lighting & Policy-Aware Shop UI | **Closed (PR #38, #42)** | Smooth Overcharged lighting tween, fail-closed `ShopCodexGui` direct bundles, 9 joint `100.00%` odds disclosure (`PR #42`), and `LayoutOrder` fix (`#19` QA). |
| **17** | P3 | 3D/Map | Biome 2–3 Maps, Glacier Yeti, Obsidian Wyrm & 8 Pets | **Open (Exports Merged)** | Blender exports/renders merged (`PR #29` / `PR #32`). **Remaining:** Open Cloud upload, `rbxassetid://` binding, & Frostbite/Caldera Studio maps. |
| **18** | P4 | Server | Launch Telemetry Hooks & Anti-Exploit Fuzz Test Suite | **Closed (PR #37, #44)** | Added `TelemetryLogic`, `TelemetryService` onboarding/bounce/opt-in/shop events + first-session cohort hardening (`PR #44`), and `SecurityInvariants.spec.luau`. |
| **19** | P4 | Client | Mobile 60 FPS Ergonomics Pass, Audio Mixing & Onboarding | **QA Verified (Ready to Close)** | Live Studio QA passed on `chore/19-studio-qa-and-handoff` (`667x375` iPhone 7, `874x402` iPhone 17 Pro, `1376x1032` iPad Pro M5, PC): fixed `HudGui` `2x2` drawer + dock overlap + `44px` `AutoAimBtn`, `HubModalsGui`/`ShopCodexGui` `LayoutOrder` + wrapping, verified `OnboardingGuideBeam`, `AudioCatalog`, `1.20ms` heartbeat, and restricted/unrestricted `PolicyService`. |
| **20** | P4 | 3D/Map | Launch Art Package (Thumbnails, Icon, Cosmetics & Plot Themes) | **Closed (PR #40)** | Merged 13 UI PNGs (`game/assets/ui/`), 4 cosmetic QA renders (`game/assets/renders/`), cosmetic VFX, `RoyalMarblePlot`, and `CosmeticsAndThemes.spec.luau`. |

---

## 3. Remaining Manual Studio / Open Cloud / Creator Hub Launch Checklist

All Luau systems, unit specs, CI checks, and Blender exports are on `main` (plus Issue `#19` UI QA fixes on `chore/19-studio-qa-and-handoff`, synced to Studio Team Create `v73`). Complete these remaining external steps before public launch:

1. **Open Cloud 3D Mesh & Animation Upload (`#13`, `#17`):**
   - Save a Roblox Open Cloud Assets API key (read+write) to `~/.config/roblox/opencloud.key` (never commit API keys to Git), or upload via Studio `open_cloud_invoke` with `asset:read` + `asset:write` scopes.
   - Upload the `.glb` / `.fbx` assets in `game/assets/exports/` (bosses, mobs, pets, eggs, balls) to Roblox Creator Store, bind published `rbxassetid://` IDs into `ReplicatedStorage.Assets` / Studio rigs, and confirm `ProceduralModels.luau` renders published meshes cleanly.
2. **Interactive Roblox Studio Map Art (`#13`, `#17`):**
   - Finish Hub Plaza props and Tier 1–3 Personal Plot aesthetics in `Workspace.BallBrawl_Map_v2` (8 plots synced with `PlotService.luau`).
   - Finalize **Frostbite Cavern** and **Molten Caldera** `PvELayer` and `BossPvPArena` terrain, lighting, and cover pillars while keeping all `26` `CollectionService` tags from [TEAM_WORKFLOW_3P.md](TEAM_WORKFLOW_3P.md) intact.
3. **Sync into Team Create (`Throw-a-ball`) — Completed (2026-11-24, `v73`):**
   - Synced all `38/38` `.luau` scripts (SHA-256 verified) into Team Create (`placeId: 76642126183926`, saved at version `73`), removed stale `ReplicatedStorage.Shared_OursPendingRemoval`, and preserved `Workspace.BallBrawl_Map_v2` & `ReplicatedStorage.Assets` via `"$ignoreUnknownInstances": true` in [game/default.project.json](../game/default.project.json).
4. **Creator Hub Monetization & Publishing Setup:**
   - Replace placeholder `passId` (`190001001`–`190001005`) and `devProductId` (`190000101`, `190000102`, `190000201`, `190000202`) values in [MonetizationConfigs.luau](../game/src/shared/Configs/MonetizationConfigs.luau) and [EggConfigs.luau](../game/src/shared/Configs/EggConfigs.luau) with live Creator Hub product IDs.
   - Upload the 13 PNGs from `game/assets/ui/` (3 thumbnails, `GameIcon_512.png`, 5 `GamePass_*.png`, and 4 `Badge_*.png`) in Creator Hub, and confirm `DataStoreService` and `AnalyticsService` are enabled on the published experience.
5. **Live Studio Device Simulator, Policy QA & P1 Hardening — Completed (2026-11-24):**
   - Resolved all 7 pre-release P1 hardening items in PRs `#42`–`#44` (`PetIncomeService` fail-closed paid-egg hatch guard, `ShopCodexGui` 9 joint `100.00%` odds disclosure, `ArenaCycleService` scramble deadline + authored room bounds, `CombatService` homing world sweep, `PlotService` vertical pad + 8-plot capacity alignment, `DataService` departure lease retry/`BindToClose`, and `TelemetryService` first-session/offer cohort fixes).
   - Verified live Studio playtests across `iphone_7` (`667x375`), `iphone_17_pro` (`874x402`), `ipad_pro_M5_13in` (`1376x1032`), and PC (`default`) with zero game script errors, `1.20ms` heartbeat script time, `OnboardingGuideBeam` Step 1→3 flow, `AudioCatalog` mode cycling, and unrestricted vs `Test_RestrictRandom = true` `DirectBundle` fallback + `PolicyLogic` receipt verification. **Issue `#19` is ready to close** once `chore/19-studio-qa-and-handoff` merges via PR.

---

## 4. Quick Local Dev Commands (All Teammates)

```bash
# 1. One-time machine setup (installs Rokit: Rojo, StyLua, Selene, Lune)
python3 scripts/setup_team.py

# 2. Mandatory quality gate before every commit / PR (StyLua + Selene + Lune + Rojo build)
python3 scripts/check.py

# 3. Cross-platform Python tooling unit tests
python3 -m unittest discover -s scripts/tests -v

# 4. Sync scripts into a LOCAL .rbxl snapshot in Roblox Studio (never two rojo serves on live Team Create!)
cd game && rojo serve

# 5. Run any headless Blender asset script (one at a time)
python3 scripts/blender_run.py game/assets/blender/<script>.py
```

---

## 5. Architecture Reference — What Lives Where on `main`

- **Shared Configs (`game/src/shared/Configs/`, 6 modules):**
  `BiomeConfigs`, `EconomyConfigs`, `EggConfigs`, `MonetizationConfigs`, `PetConfigs`, `TraitConfigs`
- **Shared Net (`game/src/shared/Net/`, 1 module):**
  `Remotes.luau` (`BallBrawlRemotes`: 17 `RemoteEvent`s + `GetInitialState` `RemoteFunction`)
- **Shared Utils (`game/src/shared/Utils/`, 9 modules):**
  - 7 pure Lune-testable logic modules: `ArenaCycleLogic`, `CombatLogic`, `EconomyLogic`, `MathUtil`, `OnboardingLogic`, `PolicyLogic`, `TelemetryLogic`
  - 2 Roblox client/asset helpers: `AudioCatalog`, `ProceduralModels`
- **Server (`game/src/server/init.server.luau` + 9 Services in `game/src/server/Services/`):**
  `ArenaCycleService`, `BossAIService`, `CombatService`, `DataService`, `EconomyService`, `PetIncomeService`, `PlotService`, `PolicyGuardService`, `TelemetryService`
- **Client (`game/src/client/init.client.luau` + 6 Controllers + 5 UI modules):**
  - **Controllers (`game/src/client/Controllers/`):** `AnimationController`, `ArenaHUDController`, `BallThrowController`, `HatchVFXController`, `OnboardingGuideController`, `PlotCashController`
  - **UI (`game/src/client/UI/`):** `HubModalsGui`, `HudGui`, `HudIcons`, `ShopCodexGui`, `Theme`
- **Lune Unit Specs (`game/tests/`, 9 passing `*.spec.luau` suites):**
  `ArenaCycleLogic.spec.luau`, `CombatAndEconomyLogic.spec.luau`, `ConfigsAndPolicy.spec.luau`, `CosmeticsAndThemes.spec.luau`, `EconomyConfigs.spec.luau`, `OnboardingLogic.spec.luau`, `SecurityFuzz.spec.luau`, `SecurityInvariants.spec.luau`, `TelemetryLogic.spec.luau`
- **Python Tooling Tests (`scripts/tests/`):**
  `test_cross_platform_scripts.py` (7 passing tests)
