# Ball Brawl: Boss Eggs — Team Handoff & Project Status

**Last Updated:** 2026-11-24 (`main @ bccd550`, PRs `#21`–`#40` merged)

**Canonical Design Spec:** [GameIdea_Evolved_GDD.md](GameIdea_Evolved_GDD.md) (`v1.1`)

**Team Workflow & Contracts:** [TEAM_WORKFLOW_3P.md](TEAM_WORKFLOW_3P.md) · [TEAM_SETUP.md](TEAM_SETUP.md)

This document is the single source of truth for **what is merged and verified on `main`**, **current GitHub issue status (`#1`–`#20`)**, **remaining manual Roblox Studio / Open Cloud / Creator Hub launch steps**, and the **live module architecture**.

---

## 1. Executive Summary — Where the Game Stands Today

- **Server Authority, Economy & Telemetry (`#1`, `#4`, `#5`, `#9`, `#10`, `#14`, `#15`, `#18`): Complete on `main`**
  All 9 server services (`DataService`, `PolicyGuardService`, `PlotService`, `ArenaCycleService`, `BossAIService`, `CombatService`, `PetIncomeService`, `EconomyService`, `TelemetryService`) are merged on `main` with `--!strict`, lease-token DataStore session locking, fail-closed Roblox 2026 `PolicyService` compliance, atomic `ProcessReceipt` handling, locked-room PvP containment, and launch funnel/bounce telemetry (`TelemetryLogic`, PR `#37`).
- **Client UI, Combat, Shop & 0–5m Onboarding (`#2`, `#6`, `#7`, `#11`, `#12`, `#16`, `#19`): Code Merged on `main` (Live Studio QA Open on `#19`)**
  Following PR `#36` (`GabWork`), PR `#38` (`#16`), PR `#39` (`#19`), and PR `#40` (`#20`), all 6 client controllers (`AnimationController`, `ArenaHUDController`, `BallThrowController`, `HatchVFXController`, `OnboardingGuideController`, `PlotCashController`) and 5 UI modules (`HudGui`, `HudIcons`, `HubModalsGui`, `ShopCodexGui`, `Theme`) are merged on `main`. Issue `#19` stays open for live Roblox Studio Device Simulator (`~667x375`) 60 FPS QA and restricted-policy (`ArePaidRandomItemsRestricted = true`) account playtesting.
- **3D Assets & Launch Art (`#3`, `#8`, `#13`, `#17`, `#20`): Blender Exports & Launch Art Merged; Open Cloud Upload & Biome 2–3 Studio Art Open**
  All 39 Blender 5.x scripts (`game/assets/blender/`), 35 `.fbx` / 36 `.glb` exports (`game/assets/exports/`), 40 preview/QA renders (`game/assets/renders/`), and 13 Cycles launch UI assets (`game/assets/ui/`: 3 × 16:9 thumbnails, 512×512 game icon, 5 Game Pass icons, and 4 Badge icons) are merged on `main` (PR `#29`, PR `#32`, PR `#36`, PR `#40`). Issues `#13` and `#17` remain open solely for Roblox Open Cloud asset upload (blocked until `~/.config/roblox/opencloud.key` is configured) and interactive Roblox Studio Hub / Biome 2–3 map art finishing.

---

## 2. Complete Issue Status Matrix (`#1`–`#20`)

| # | Phase | Role | Issue | Status | Notes / What Remains |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | P0 | Server | Shared Configs & Typed Remotes | **Closed** | All 6 config modules (`Biome`, `Economy`, `Egg`, `Monetization`, `Pet`, `Trait`) & `Remotes.luau` live on `main`. |
| **2** | P0 | Client | Client Bootstrap & Remote Wrapper | **Closed (PR #21)** | Merged (`PR #21`) and evolved via `PR #33` / `PR #36` into `init.client.luau` + `Controllers/` + `UI/`. |
| **3** | P0 | 3D/Map | Hub Plaza & Meadow Greybox (`BallBrawl_Map_v2`) | **Closed** | `Workspace.BallBrawl_Map_v2` imported in Studio with `26` `CollectionService` tags matching `TEAM_WORKFLOW_3P.md`. |
| **4** | P1 | Server | `ArenaCycleService` (3-Phase FSM, 5s Claim, Storm) | **Closed (PR #23)** | Hardened in `PR #37` with room bounds, entrant pre-pruning, atomic opt-in switching, and single payout settlement. |
| **5** | P1 | Server | `CombatService` & `BossAIService` (Mossback Golem) | **Closed (PR #24)** | Evolved with ballistic/homing throws (`PR #35`, `PR #36`), arena-validated damage (`PR #37`), and KO position capture (`PR #40`). |
| **6** | P1 | Client | `BallThrowController` (Training, Dodge, Aim Assist) | **Closed (PR #22)** | Evolved with PC camera aim (`PR #34`), live bounce rebound (`PR #35`), 60 FPS animations (`PR #36`), and cosmetic VFX (`PR #40`). |
| **7** | P1 | Client | `ArenaHUDController` (Banner, Opt-In, 5s Ring) | **Closed (PR #24)** | Updated with tweened Overcharged lighting and 44px mobile claim ergonomics (`PR #38`). |
| **8** | P1 | 3D/Map | Meadow 3D Assets (Golem, Mobs, Balls, Boss Egg) | **Closed (PR #29)** | Blender exports/renders merged (`PR #29`, `PR #32`, `PR #36`). Studio `rbxassetid://` binding tracked under `#13` / `#17`. |
| **9** | P2 | Server | `DataService` & `EconomyService` (Persistence, Ascension) | **Closed (PR #25)** | Hardened in `PR #37` with lease-token locking, Studio-only memory fallback, and finite/overflow ledger guards. |
| **10** | P2 | Server | `PetIncomeService` & `PlotService` (Cash Pads, Offline, Fusion) | **Closed (PR #26)** | Hardened in `PR #37` and updated in `PR #40` with theme-only refresh, pet rig reuse, and vacant plot material restore. |
| **11** | P2 | Client | `PlotCashController`, `HatchVFXController` & Followers | **Closed (PR #30)** | Evolved with `AudioCatalog` chimes, `AnimationController` (`PR #36`), and `SupernovaHatch` beam VFX (`PR #40`). |
| **12** | P2 | Client | Hub Progression UIs (`HubModalsGui`) | **Closed (PR #36)** | Pets (Lv 1–25, Fusion, Traits, Followers, Pedestals), Eggs/Crafting, and Upgrades/Ascension tabs live in `HubModalsGui.luau`. |
| **13** | P2 | 3D/Map | Hub Plaza Art, Tier 1–3 Plots & Starter/Meadow Pets | **Open (Exports Merged)** | Blender assets merged (`PR #29` / `PR #32`). **Remaining:** Open Cloud upload (`~/.config/roblox/opencloud.key`) + Studio Hub/Plot art pass. |
| **14** | P3 | Server | 5-Min Overcharged Scheduler, Biome 2–3 Bosses & Active Perks | **Closed (PR #27)** | Live across `ArenaCycleLogic`, `BossAIService`, `CombatLogic`, and `ArenaHUDController`. |
| **15** | P3 | Server | `PolicyGuardService` & Exactly-Once `ProcessReceipt` | **Closed (PR #28)** | Hardened in `PR #37` with fail-closed policy lookup tokens and durable committed receipt checks. |
| **16** | P3 | Client | Codex UI, Overcharged Lighting & Policy-Aware Shop UI | **Closed (PR #38)** | Smooth Overcharged lighting tween, fail-closed `ShopCodexGui` direct bundles, `100%` odds, and mobile card fixes merged. |
| **17** | P3 | 3D/Map | Biome 2–3 Maps, Glacier Yeti, Obsidian Wyrm & 8 Pets | **Open (Exports Merged)** | Blender exports/renders merged (`PR #29` / `PR #32`). **Remaining:** Open Cloud upload, `rbxassetid://` binding, & Frostbite/Caldera Studio maps. |
| **18** | P4 | Server | Launch Telemetry Hooks & Anti-Exploit Fuzz Test Suite | **Closed (PR #37)** | Added `TelemetryLogic`, `TelemetryService` onboarding/bounce/opt-in/shop events, `SecurityInvariants.spec.luau`, and P0/P1 fixes. |
| **19** | P4 | Client | Mobile 60 FPS Ergonomics Pass, Audio Mixing & Onboarding | **Open (Code Merged PR #39)** | `OnboardingLogic`, pooled `OnboardingGuideController` floor beam, and `HudGui` mobile wrap merged. **Remaining:** live Studio Device Simulator & policy QA. |
| **20** | P4 | 3D/Map | Launch Art Package (Thumbnails, Icon, Cosmetics & Plot Themes) | **Closed (PR #40)** | Merged 13 UI PNGs (`game/assets/ui/`), 4 cosmetic QA renders (`game/assets/renders/`), cosmetic VFX, `RoyalMarblePlot`, and `CosmeticsAndThemes.spec.luau`. |

---

## 3. Remaining Manual Studio / Open Cloud / Creator Hub Launch Checklist

All Luau systems, unit specs, CI checks, and Blender exports are on `main`. Complete these manual external steps before public launch:

1. **Open Cloud 3D Mesh & Animation Upload (`#13`, `#17`):**
   - Save a Roblox Open Cloud Assets API key (read+write) to `~/.config/roblox/opencloud.key` (never commit API keys to Git).
   - Upload the `.glb` / `.fbx` assets in `game/assets/exports/` (bosses, mobs, pets, eggs, balls) to Roblox Creator Store, bind published `rbxassetid://` IDs into `ReplicatedStorage.Assets` / Studio rigs, and confirm `ProceduralModels.luau` renders published meshes cleanly.
2. **Interactive Roblox Studio Map Art (`#13`, `#17`):**
   - Finish Hub Plaza props and Tier 1–3 Personal Plot aesthetics in `Workspace.BallBrawl_Map_v2` (confirming 8 vs. 12 plot capacity matches `PlotService.luau`).
   - Finalize **Frostbite Cavern** and **Molten Caldera** `PvELayer` and `BossPvPArena` terrain, lighting, and cover pillars while keeping all `26` `CollectionService` tags from [TEAM_WORKFLOW_3P.md](TEAM_WORKFLOW_3P.md) intact.
3. **Sync `main` into Team Create (`Throw-a-ball`):**
   - Verify `"$ignoreUnknownInstances": true` in [game/default.project.json](../game/default.project.json) and have **one designated engineer** run `cd game && rojo serve` against Team Create (`placeId: 76642126183926`) so Studio-built maps and `ReplicatedStorage.Assets` are preserved cleanly.
4. **Creator Hub Monetization & Publishing Setup:**
   - Replace placeholder `passId` (`190001001`–`190001005`) and `devProductId` (`190000101`, `190000102`, `190000201`, `190000202`) values in `game/src/shared/Configs/MonetizationConfigs.luau` and `game/src/shared/Configs/EggConfigs.luau` with live Creator Hub product IDs.
   - Upload the 13 PNGs from `game/assets/ui/` (3 thumbnails, `GameIcon_512.png`, 5 `GamePass_*.png`, and 4 `Badge_*.png`) in Creator Hub, and confirm `DataStoreService` and `AnalyticsService` are enabled on the published experience.
5. **Live Studio Device Simulator & Policy QA (`#19` Close Gate):**
   - Playtest end-to-end in Roblox Studio Device Simulator (small phone `~667x375` + tablet + PC): confirm 60 FPS performance, touch button spacing, full `0–5m` onboarding guide flow, audio mix levels, and cosmetic VFX / `RoyalMarblePlot` behavior.
   - Verify both unrestricted (`ArePaidRandomItemsRestricted = false`) 100% odds display and restricted (`Test_RestrictRandom = true` / restricted account) `DirectBundle` fallback + `ProcessReceipt` grants, then close `#19`.
   - Before wide release, review and address any deferred pre-release P1 hardening items flagged in the final audit (`PetIncomeService` policy check on owned paid-egg hatch, `ShopCodexGui` 9 joint Pet × Mutation odds view, `ArenaCycleLogic` scramble `phaseEndsAt` timeout + authored room bounds, `CombatService` homing world sweep, `PlotService` vertical pad support + plot count alignment, `DataService` failed final save retry / `BindToClose`, and `TelemetryService` first-session/offer cohort fixes).

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
