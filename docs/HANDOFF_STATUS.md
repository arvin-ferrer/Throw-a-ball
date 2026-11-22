# Ball Brawl: Boss Eggs — Team Handoff & Project Status

**Last Updated:** 2026-11-23 (`main @ 8b531ae`, PRs #21–#30 merged)  
**Canonical Design Spec:** [GameIdea_Evolved_GDD.md](GameIdea_Evolved_GDD.md) (`v1.1`)  
**Team Workflow & Contracts:** [TEAM_WORKFLOW_3P.md](TEAM_WORKFLOW_3P.md) · [TEAM_SETUP.md](TEAM_SETUP.md)

Arvin is pausing dev on his end — this document is the single source of truth for **what is already built and verified on `main`**, **how to resolve the live Team Create / branch overlap cleanly**, and **every remaining task needed to reach MVP & soft launch**.

---

## 1. Executive Summary — Where the Game Stands Today

- **Core Server & Economy Backbone: ~90% Complete (Merged on `main`)**  
  All 3 phases of gameplay, combat validation, all 3 biome bosses, mobs, ProfileStore persistence, Dual-Currency ledger (`Coins` + `Boss Gems`), Cash Pads, `<=12h` offline accrual, 3-to-1 Pet Fusion, Lv 1–25 upgrades, Traits, 5-Min Overcharged scheduler, Active Ball Perks, and Roblox 2026 `PolicyService` + exactly-once `ProcessReceipt` monetization are implemented on `main` with strict Luau (`--!strict`) and passing Lune unit tests.
- **Core Client Controllers: ~55% Complete (Merged on `main`)**  
  Client bootstrap, `ClientNet`, `MockStateHarness`, `BallThrowController` + touch UI, `ArenaHUDController` (phase banner, opt-in modal, 5s claim ring), `PlotCashController`, `HatchVFXController` (3s reveal), and `FollowerRigController` are merged. **Hub progression menus (`#12`), Codex + Policy-aware Shop UI (`#16`), and mobile/audio polish (`#19`) still need to be built.**
- **3D Assets & Studio Map: Models Exported, Studio Upload & Launch Art Pending**  
  `Workspace.BallBrawl_Map_v2` exists in Team Create. **34 Blender models** (`.fbx` + `.glb`) and **35 preview renders** covering all 3 biomes (3 rigged bosses, 6 rigged mobs, 5 ball tiers, 5 boss eggs standard/overcharged, 13 pets, boulder) are merged under `game/assets/`. They still need **Roblox asset upload** (to replace placeholder Parts in-game), a **silhouette polish pass** on older boxy models, and **#20 launch thumbnails/icon**.

---

## 2. Complete Issue Status Matrix (`#1`–`#20`)

| # | Phase | Role | Issue | Status | Notes / What Remains |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | P0 | Server | Shared Configs & Typed Remotes | **Implemented (issue open)** | All 6 config modules (`Biome`, `Combat`, `Economy`, `Monetization`, `Pet`, `Shop`) & `Remotes.luau` live on `main`. Document final remote payload contract & close issue. |
| **2** | P0 | Client | Client Bootstrap, `ClientNet` & Mock Harness | **Done (PR #21)** | Merged & closed (`@Natex15`). |
| **3** | P0 | 3D/Map | Hub Plaza & Meadow Greybox (`BallBrawl_Map_v2`) | **In Team Create (issue open)** | Map exists in Team Create (`Throw-a-ball`). Verify all 26 `CollectionService` tags match `TEAM_WORKFLOW_3P.md` & close issue. |
| **4** | P1 | Server | `ArenaCycleService` (3-Phase FSM, 5s Claim, Storm) | **Done (PR #23)** | Merged, playtested in Studio & closed. |
| **5** | P1 | Server | `CombatService` & `BossAIService` (Mossback Golem) | **Done (PR #24)** | Merged, playtested in Studio & closed. |
| **6** | P1 | Client | `BallThrowController` (Pad Lock, Dodge, Aim Assist) | **Done (PR #22)** | Merged & closed (`@Natex15`). |
| **7** | P1 | Client | `ArenaHUDController` (Banner, Opt-In, 5s Ring) | **Done (PR #24)** | Merged & closed. |
| **8** | P1 | 3D/Map | Meadow 3D Assets (Golem, Mobs, Balls, Boss Egg) | **Exported (PR #29)** | `.fbx`/`.glb` + renders in `game/assets/`. Still needs **Roblox upload** + optional organic sculpt polish on `MossbackGolem` / `BrambleBoar`. |
| **9** | P2 | Server | `DataService` & `EconomyService` (ProfileStore, Ascension) | **Done (PR #25)** | Merged & closed. |
| **10** | P2 | Server | `PetIncomeService` & `PlotService` (Cash Pads, Offline, Fusion) | **Done (PR #26)** | Merged & closed. |
| **11** | P2 | Client | `PlotCashController`, `HatchVFXController` & Followers | **Done (PR #30)** | Merged on `main@8b531ae`. (Audio upgrade via `AudioCatalog` listed in Section 4.) |
| **12** | P2 | Client | **Hub Progression UIs** (Pet Bag, Fusion, Trait Altar, Shop, Ascension) | **TODO** | Server remotes (`ShopPurchase`, `PetAction`) are ready. Build pure view-model + Lune spec + mobile-safe UI. |
| **13** | P2 | 3D/Map | Hub Plaza Art, Tier 1–3 Plots & Starter/Meadow Pets | **Pets Exported (PR #29)** | 5 Starter/Meadow pets exported. Hub art pass + Roblox upload of pet meshes still needed. |
| **14** | P3 | Server | 5-Min Overcharged Scheduler, Biome 2–3 Bosses & Active Perks | **Done (PR #27)** | Merged & closed. (Follower `Swift` / `Brawler` trait multipliers to port from teammate snapshot — see Section 4.) |
| **15** | P3 | Server | `PolicyGuardService` & Exactly-Once `ProcessReceipt` | **Done (PR #28)** | Merged on `main@36af854`. |
| **16** | P3 | Client | **Codex UI, Overcharged Skybox/Alerts & Policy-Aware Shop UI** | **TODO** | Must call `GetPolicyState` + `PolicyGuard.getOfferDisplay` so restricted regions see direct bundles (never random odds). |
| **17** | P3 | 3D/Map | Biome 2–3 Maps, Glacier Yeti, Obsidian Wyrm & 8 Pets | **Models Exported (PR #29)** | All 18 Frostbite/Caldera models exported & QA'd. Still needs Roblox upload + Biome 2–3 map art pass. |
| **18** | P4 | Server | **Launch Telemetry Hooks & Anti-Exploit Fuzz Test Suite** | **TODO** | Port `TelemetryService` (`AnalyticsService:LogCustomEvent` + `<60s` / `61-180s` / `>180s` bounce buckets) + add Lune fuzz specs for all pure validators. |
| **19** | P4 | Client | **Mobile 60 FPS Ergonomics Pass, Audio Mixing & Onboarding** | **TODO** | Device Simulator QA (Phone/Tablet), wire `AudioCatalog` SFX across combat/UI/hatch/cash pads, tune 0–5m onboarding. |
| **20** | P4 | 3D/Map | **Launch Art Package** (3× 16:9 Thumbnails, 512×512 Icon, Cosmetics) | **TODO** | Compose 3 high-CTR 16:9 thumbnails + 512×512 icon under `game/assets/launch/` (or `game/assets/ui/`) + Ball Trails / Plot Themes. |

---

## 3. IMPORTANT FIRST STEP — Team Create & Branch Conflict Resolution

Before anyone syncs scripts into the shared Team Create place **`Throw-a-ball` (`placeId: 76642126183926`)**, read this carefully so nobody loses work:

1. **What happened:** While PRs `#21`–`#30` were being merged onto `origin/main`, `@Gab172005` (`GabTheGreat` / `GabLakasTama`) pushed a parallel baseline branch **`origin/GabWork`** (`8d99ad4`, 40 files) and created **`ReplicatedStorage.Assets`** (61 Part/Mesh prefabs across `Balls`, `Targets`, `Mobs`, `Bosses`, `Eggs`, `Pets`, `VFX`, `HubProps`) plus untagged scripts in Team Create.
2. **Current live state of Team Create (`Throw-a-ball`):**
   - `ReplicatedStorage.Assets`, `Workspace.BallBrawl_Map_v2`, and `Workspace.Pyraxis` are **intact and belong to Dev C — do NOT overwrite or delete them**.
   - `ReplicatedStorage.Shared` currently contains 14 untagged modules from `GabWork` (NOT `origin/main`).
   - `ServerScriptService.Server` and `StarterPlayer.StarterPlayerScripts.Client` are currently **empty 1-line shells** (no `SyncedFrom` tag) due to concurrent writes.
   - A read-only backup of that Studio snapshot was saved on branch **`origin/teammate/teamcreate-snapshot-2026-11-23`**.
3. **Agreed Resolution Plan (Zero Lost Work):**
   - Keep **`origin/main` (`8b531ae`)** as the single tested code backbone.
   - Port the **3 unique high-value features** from `origin/GabWork` / `teammate/teamcreate-snapshot-2026-11-23` into `main` via a normal PR (details in Section 4.1 below).
   - Confirm nobody else has `rojo serve` connected to Team Create, then have **one person** pull `main` and sync `ReplicatedStorage.Shared`, `ServerScriptService.Server`, and `StarterPlayerScripts.Client` into `Throw-a-ball` cleanly.

---

## 4. Prioritized Handoff Checklist (What Still Needs To Be Done)

### Priority 1 — Port Teammate Snapshot Gems & Re-Sync Team Create (Server + Client)
Branch already created from `origin/main`: `feat/merge-teammate-teamcreate` (clean PR against `main`):
1. **`AudioCatalog`** (`game/src/shared/Utils/AudioCatalog.luau`): Port `SOUND_IDS`, `play(key, pitch?, volume?, parent?)` (pitch clamp `0.5–2.2`, volume `0–1.5`, `RollOffMaxDistance = 85`, destroy after `2.5s`), and `playCashSweep(step)`. Wire into `PlotCashController` (using `CashPadView.chimePitch`) and `HatchVFXController`.
2. **Follower Trait Multipliers (`Swift` & `Brawler`)**: Add pure `ActivePerks.traitMultipliers(pets) -> (damageMult, throwSpeedMult)` (`Brawler = +8%` Ball Damage, `Swift = +10%` Throw Speed per active follower) + Lune tests in `game/tests/ActivePerks.spec.luau`, then apply in `PerkService.rollHit` and `CombatService` (`getThrowSpeedMultiplier` hook).
3. **`TelemetryService` (`#18` part 1)**: Wrap `AnalyticsService:LogCustomEvent` in `pcall`, track session bounce buckets (`<60s` / `61–180s` / `>180s`), expose `record(event, player, value)`, and wire Arena Win, Arena Participation, Shop Purchase, Egg Hatch, and Soft Ascension.
4. **One Clean Sync to Team Create:** After merging, sync `main` into `"Throw-a-ball"` and verify playtest with 0 errors.

### Priority 2 — Remaining Client UIs & Polish (`@Natex15` / Dev B)
Follow the existing pure view-model + Lune spec + thin Roblox UI pattern (`ArenaHUDViewModel.luau` + `ArenaHUDController.luau`):
- **`#12` Hub Progression UIs:**
  - Pet Inventory / Equip Followers (`PetAction`: `"Equip"` / `"Unequip"`, 1/2/3 slots at Lv 1/10/25)
  - 3-to-1 Pet Fusion & Lv 1–25 Upgrade UI (`PetAction`: `"Fuse"`, `"LevelUp"`, `"Place"`, `"Remove"`)
  - Trait Altar (`PetAction`: `"RerollTrait"`, 5 Boss Gems)
  - Ball / Target / Pedestal / Vault / Gem Egg / Soft Ascension Shop (`ShopPurchase`: `"BallTier"`, `"TargetTier"`, `"Pedestal"`, `"OfflineVault"`, `"GemEgg"`, `"Ascend"`)
- **`#16` Codex, Overcharged Alerts & Compliant Shop UI:**
  - Pet & Mutation Codex panel tracking discovered species/mutations
  - 5-Min Overcharged global countdown banner + skybox/lighting alert
  - **Roblox 2026 Compliance:** Call `GetPolicyState` RemoteFunction on open and render through `PolicyGuard.getOfferDisplay` — restricted regions must NEVER see paid random egg odds and must see direct bundles instead; unrestricted regions must show exact `100%` odds tables.
- **`#19` Mobile 60 FPS & Audio Polish:**
  - Verify `Scale` sizing, `44px+` touch targets, safe area insets, and zero overlap with Jump/Thumbstick in Roblox Studio Device Simulator (Phone & Tablet).
  - Connect `AudioCatalog` SFX across throws, hits, gold target combos, boss telegraphs, and victory.

### Priority 3 — Server Hardening & Issue Cleanup (Dev A / Server)
- **`#18` Anti-Exploit Fuzz Suite:** Add Lune fuzz tests feeding `NaN`, `inf`, `-inf`, huge tables, wrong types, negative numbers, and replayed ids into `CombatMath.validateThrowPayload`, `PolicyGuard`, `PurchaseLedger`, `PetFusion`, and `EconomyLedger` — assert clean rejection with zero state mutation.
- **`#1` Remotes Contract Doc:** Document every event/function payload in `game/src/shared/Net/Remotes.luau` and close `#1`.

### Priority 4 — 3D Asset Upload, Silhouette Polish & Launch Art (`@Gab172005` / Dev C)
- **`#3` Tag Audit:** Verify all 26 `CollectionService` tags in `Workspace.BallBrawl_Map_v2` resolve cleanly and close `#3`.
- **Upload 3D Models to Roblox:**
  - All 34 Blender `.fbx` / `.glb` models are ready in `game/assets/exports/` (with preview PNGs in `game/assets/renders/`).
  - Currently bosses/mobs render as placeholder Parts on `main` until uploaded to Roblox and placed in `ServerStorage.BossModels` / `ServerStorage.MobModels` (or mapped to `ReplicatedStorage.Assets` once models are upgraded).
  - *(Note: Automated bulk upload requires a Roblox Open Cloud Assets API key saved locally — never commit API keys to Git.)*
- **Optional Art Polish Pass:** Replace remaining rectangular box limbs (`PebbleCub`, `PermafrostBear`, `LavaRhino`, `BrambleBoar`, `CrystalWolf`, `MagmaHound`, `CinderImp`, `ObsidianWyrm`) with sculpted `add_lofted_tube` forms matching `Pyraxis_live_preview.png` and saturated biome accents (Meadow emerald, Frostbite ice-cyan, Caldera lava-orange). *(Arvin's local `git stash@{0}` `wip-boss-art-polish` has early organic sculpt upgrades for `MossbackGolem` & `GlacierYeti` if desired.)*
- **`#20` Launch Art Package:** Create 3 × 16:9 Roblox Home Thumbnails + 1 × 512×512 Game Icon under `game/assets/ui/` (or `game/assets/launch/`), plus cosmetic Ball Trails and Plot Themes.

---

## 5. Quick Local Dev Commands (All Teammates)

```bash
# 1. One-time machine setup (installs Rokit: Rojo, StyLua, Selene, Lune)
python scripts/setup_team.py

# 2. Mandatory quality gate before every commit / PR (StyLua + Selene + Lune + Rojo build)
python scripts/check.py

# 3. Sync scripts into a LOCAL .rbxl snapshot in Roblox Studio (never two rojo serves on live Team Create!)
cd game && rojo serve

# 4. Run any headless Blender asset script (one at a time)
python scripts/blender_run.py game/assets/blender/<script>.py
```

---

## 6. Architecture Reference — What Lives Where on `main`

- **Shared Configs (`game/src/shared/Configs/`):** `BiomeConfigs`, `CombatConfigs`, `EconomyConfigs`, `MonetizationConfigs`, `PetConfigs`, `ShopConfigs`
- **Shared Net (`game/src/shared/Net/`):** `Remotes.luau`
- **Pure Testable Logic (`game/src/shared/Utils/`):** `ArenaStateMachine`, `CombatMath`, `BossAIStateMachine`, `ProjectileArc`, `ArenaHUDViewModel`, `EconomyLedger`, `PetIncome`, `PetFusion`, `CashPadView`, `ActivePerks`, `PolicyGuard`, `PurchaseLedger`, `ClientNet`
- **Server Services (`game/src/server/Services/`):** `ArenaCycleService`, `BossAIService`, `CombatService`, `MobService`, `PortalService`, `DataService`, `EconomyService`, `PetIncomeService`, `PlotService`, `PerkService`, `PolicyGuardService`
- **Client Controllers & UI (`game/src/client/`):** `ClientLifecycle`, `MockStateHarness`, `BallThrowController` (+ `BallThrowTouchUI`), `ArenaHUDController` (+ `ArenaHUDView`), `PlotCashController`, `HatchVFXController`, `FollowerRigController`
- **Lune Unit Specs (`game/tests/`):** 16 passing `*.spec.luau` files covering every pure module on `main`.
