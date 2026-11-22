# Deliverable D — Successful Game Feature Matrix

**Collection Date:** `2026-11-22`  
**Backed By:** [feature_matrix.csv](../data/feature_matrix.csv) (`44` verified Roblox games × `41` mechanics from Section 4 of `Research.txt`, validated & computed programmatically by [validate_research_data.py](../scripts/validate_research_data.py)).

---

## 1. Python-Computed 41-Mechanic Prevalence Matrix (`n = 44`)

Cohorts compared below:
- **Overall (`n = 44`)**: All 44 verified Roblox experiences across all 6 categories.
- **Viral (`n = 10`)**: `Recently viral games` (2025–2026 explosive breakouts).
- **Sustained (`n = 15`)**: `Established market leaders` (8) + `Sustainable mid-sized games` (7).
- **Simple-Hit (`n = 6`)**: `Simple-mechanic disproportionate results`.

| Rank | Mechanic | Group | Count (`n=44`) | Overall % | Viral % | Sustained % | Simple-Hit % | Solo Dev Cost |
| :-: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | :--- |
| 1 | `social_recognition` | Engagement | 44 | **100.0%** | 100.0% | 100.0% | 100.0% | Low |
| 2 | `visible_player_progression` | Engagement | 42 | **95.5%** | 100.0% | 86.7% | 100.0% | Low |
| 3 | `timed_events` | Engagement | 39 | **88.6%** | 90.0% | 86.7% | 83.3% | Low–Med |
| 4 | `leaderboards` | Progression | 37 | **84.1%** | 100.0% | 60.0% | 100.0% | Low |
| 5 | `limited_time_content` | Engagement | 37 | **84.1%** | 90.0% | 73.3% | 83.3% | Medium |
| 6 | `collection_mechanics` | Core | 30 | **68.2%** | 70.0% | 40.0% | 66.7% | Low–Med |
| 7 | `cooperation` | Core | 30 | **68.2%** | 40.0% | **93.3%** | 33.3% | Medium |
| 8 | `rarity_systems` | Progression | 30 | **68.2%** | 80.0% | 40.0% | 83.3% | Low |
| 9 | `achievements` | Progression | 29 | **65.9%** | 50.0% | **86.7%** | 50.0% | Low |
| 10 | `randomized_rewards` | Core | 29 | **65.9%** | 80.0% | 46.7% | 83.3% | Low *(High Legal!)* |
| 11 | `collection_completion` | Engagement | 28 | **63.6%** | 70.0% | 40.0% | 50.0% | Low |
| 12 | `equipment_upgrades` | Progression | 28 | **63.6%** | 70.0% | 40.0% | 83.3% | Low–Med |
| 13 | `rare_item_discoveries` | Engagement | 26 | **59.1%** | 70.0% | 40.0% | 66.7% | Low |
| 14 | `area_biome_unlocks` | Progression | 22 | **50.0%** | 60.0% | 33.3% | 66.7% | High *(Art Treadmill)* |
| 15 | `cooperative_objectives` | Engagement | 22 | **50.0%** | 40.0% | 40.0% | 33.3% | Medium |
| 16 | `daily_weekly_quests` | Progression | 22 | **50.0%** | 40.0% | 40.0% | 33.3% | Low |
| 17 | `random_events` | Engagement | 22 | **50.0%** | 70.0% | 46.7% | 50.0% | Low–Med |
| 18 | `combat` | Core | 21 | **47.7%** | 70.0% | 40.0% | 16.7% | Med–High |
| 19 | `levels_xp` | Progression | 20 | **45.5%** | 40.0% | 53.3% | 16.7% | Low |
| 20 | `base_building` | Core | 19 | **43.2%** | 60.0% | 46.7% | 50.0% | Med–High |
| 21 | `competition` | Core | 19 | **43.2%** | 50.0% | 46.7% | 0.0% | Medium |
| 22 | `multiple_currencies` | Progression | 19 | **43.2%** | 30.0% | **66.7%** | 16.7% | Low–Med |
| 23 | `daily_rewards` | Engagement | 18 | **40.9%** | 20.0% | 40.0% | 33.3% | Low |
| 24 | `meaningful_competition` | Engagement | 18 | **40.9%** | 50.0% | 46.7% | 0.0% | Medium |
| 25 | `server_wide_announcements` | Engagement | 17 | **38.6%** | **50.0%** | 13.3% | 50.0% | Very Low |
| 26 | `exploration` | Core | 15 | **34.1%** | 30.0% | 33.3% | 50.0% | High |
| 27 | `boss_battles` | Core | 13 | **29.5%** | 30.0% | 33.3% | **0.0%** | Med–High |
| 28 | `idle_passive_progression` | Core | 13 | **29.5%** | **50.0%** | 13.3% | 50.0% | Low |
| 29 | `resource_gathering` | Core | 13 | **29.5%** | 30.0% | 20.0% | 50.0% | Low–Med |
| 30 | `survival` | Core | 13 | **29.5%** | 40.0% | 26.7% | 33.3% | Medium |
| 31 | `trading` | Core | 11 | **25.0%** | **0.0%** | **33.3%** | 16.7% | High *(Anti-Dupe)* |
| 32 | `clicking_repetitive` | Core | 10 | **22.7%** | 30.0% | 13.3% | 33.3% | Very Low |
| 33 | `damage_scaling` | Progression | 10 | **22.7%** | 30.0% | 20.0% | **0.0%** | Low |
| 34 | `pets_companions` | Progression | 9 | **20.5%** | 20.0% | 20.0% | 16.7% | Medium |
| 35 | `tycoon_mechanics` | Core | 9 | **20.5%** | **40.0%** | 6.7% | 33.3% | Low–Med |
| 36 | `rebirths_prestige` | Progression | 8 | **18.2%** | **40.0%** | 13.3% | **0.0%** | Low |
| 37 | `egg_hatching` | Progression | 7 | **15.9%** | 10.0% | 13.3% | 16.7% | Med *(Legal Gate)* |
| 38 | `offline_progression` | Engagement | 7 | **15.9%** | **40.0%** | **0.0%** | 16.7% | Low |
| 39 | `skill_trees` | Progression | 6 | **13.6%** | 0.0% | **26.7%** | 0.0% | Medium |
| 40 | `training_attribute_grinding` | Core | 6 | **13.6%** | 20.0% | 13.3% | 16.7% | Low |
| 41 | `stealing_raiding` | Core | 4 | **9.1%** | 20.0% | **0.0%** | 16.7% | Medium |

---

## 2. Diagnostic Answers to All 8 Section 4 Strategic Questions

### 1. Which features appear most frequently? `[Observational correlation]`
The top 5 mechanics across all 44 experiences are **pure visibility and live-ops scaffolding** rather than specific gameplay verbs:
1. **`social_recognition` (100.0%)** — Every single successful game makes status, rank, outfits, bases, wins, or rare items visible to other players in shared spaces.
2. **`visible_player_progression` (95.5%)** — Progress manifests physically in the 3D world (growing base, rarer weapons/auras, taller climb, expanded campfire) rather than buried inside text menus.
3. **`timed_events` (88.6%)** & **`limited_time_content` (84.1%)** — Synchronized events and rotating catalogs create shared return appointments.
4. **`leaderboards` (84.1%)** — Low-cost social comparison anchors.

### 2. Which features are associated with rapid viral growth? `[Observational correlation]`
Comparing `Viral %` against `Sustained %` exposes the exact **2025–2026 Viral Spike Blueprint**:
- **`offline_progression` (40.0% Viral vs. 0.0% Sustained)** — *"Your garden/animals earn while you're offline!"* drives explosive D1 check-ins (`Grow a Garden`, `Steal An Egg`, `Throw Food For Animals`, `Plants vs Brainrots`).
- **`server_wide_announcements` (50.0% Viral vs. 13.3% Sustained)** & **`random_events` (70.0% Viral vs. 46.7% Sustained)** — Weather mutations, global secret catches, and Admin Abuse spectacles generate instant clip-worthy peaks.
- **`randomized_rewards` (80.0% Viral vs. 46.7% Sustained)** & **`rarity_systems` (80.0% vs. 40.0%)** — Lottery-style anticipation sparks TikTok/YouTube reaction screams.
- **`idle_passive_progression` (50.0% vs. 13.3%)**, **`tycoon_mechanics` (40.0% vs. 6.7%)**, **`rebirths_prestige` (40.0% vs. 13.3%)**, and **`stealing_raiding` (20.0% vs. 0.0%)** — Ultra-fast dopamine acceleration, frequently accompanied by steep post-peak contractions (`-99.8%` to `-99.96%`).

### 3. Which features appear associated with sustained multi-year success? `[Strongly supported by evidence]` `[Observational correlation]`
The **Sustained** cohort (`Established Leaders` + `Sustainable Mid-Sized`, `n = 15`) separates dramatically from transient spikes on five axes:
- **`cooperation` (93.3% Sustained vs. 40.0% Viral!)** — The single strongest structural differentiator in the entire 44-game dataset. Directly aligns with Roblox's official June 2026 **Intentional Co-Play Days** RFY ranking signal (`S03`).
- **`achievements` (86.7% Sustained vs. 50.0% Viral)** — Structured mastery milestones extending gameplay across months without needing exponential power creep.
- **`multiple_currencies` (66.7% vs. 30.0%)** & **`levels_xp` (53.3% vs. 40.0%)** — Layered economies separating soft grind currency from prestige/cosmetic/meta currency to prevent rapid hyperinflation.
- **`trading` (33.3% Sustained vs. 0.0% Viral)** & **`skill_trees` (26.7% vs. 0.0%)** — Mature community economies and deep build specialization (*Adopt Me!*, *MM2*, *Blox Fruits*, *Bee Swarm*, *Deepwoken*) create huge switching costs (note: trading carries severe anti-dupe engineering risk for solo devs).

### 4. Which features are becoming oversaturated? `[Strongly supported by evidence]`
- **`clicking_repetitive` (22.7%)**, **`training_attribute_grinding` (13.6%)**, and **`egg_hatching` (15.9%)**: Notice how *rare* pure training-and-egg-hatching actually is among late-2026 top performers—and of the 7 egg-hatching games in the database, two (*Grow a Garden*, *Pet Simulator 99!*) are actively **declining**, two (*Adopt Me!*, *Bee Swarm*) are 8–9 year entrenched incumbents, and the breakout (*Steal An Egg*) is backed by Do Big Studios' mega-LiveOps network (`S14`, `S24`).
- **Generic `randomized_rewards` tied to Robux:** Not only mechanically saturated, but now aggressively gated by global **Paid Random Items** laws (`PolicyService` bans across BE, NL, UK `<18`, AU `<18`, and Brazil `<18`/unverified since March 17, 2026) (`S08`).
- **Pure `rebirths_prestige` loops** without skill/social depth (*Plants vs Brainrots* collapsed `-99.96%` despite Rebirth luck multipliers).

### 5. Which features work especially well together (High-Synergy Combos)? `[Strongly supported by evidence]` `[Reasonable inference]`
1. **Co-op Survival (`cooperation` + `survival` + `cooperative_objectives`) + Meta Class Unlocks (`equipment_upgrades` + `achievements`)**: *99 Nights in the Forest* (120k–204k CCU), *Dandy's World* (113k–191k), *Dead Rails*, *DOORS*. High session length, elite 28-day retention, low content treadmill.
2. **Instant Physical Matchmaking (`meaningful_competition` + `social_recognition`) + Pure Cosmetics (`collection_mechanics` + `daily_weekly_quests`)**: *RIVALS* (110k–200k), *Illegal Soccer* (>40% peak retention!), *Volleyball Legends* (95.17% rating).
3. **Active Tactile Minigame (`resource_gathering`) + Deep Bestiary (`collection_completion` + `rare_item_discoveries`) + Shared World Events (`random_events` + `server_wide_announcements`)**: *Fisch* (40k–70k), *Fish It!* (65k–81k).
4. **Risk-Reward Extraction (`survival`/`stealing_raiding`) + Visible Base Display (`base_building` + `visible_player_progression`) + Bounded Async Income (`offline_progression`)**: *Steal An Egg*, *Climb For Animals Eggs* (98.6% rating).

### 6. Which features are common table stakes that do NOT differentiate? `[Reasonable inference]`
- **`leaderboards` (84.1%)**, **`daily_rewards` (40.9%)**, **`daily_weekly_quests` (50.0%)**, **`levels_xp` (45.5%)**, and generic **`rarity_systems` (68.2%)**: Players expect them as hygiene defaults, but adding a daily login popup or Common→Mythic color gradient will never convince a player to stay past minute 3 if the core verb is dull.

### 7. Which features are expensive to develop relative to their solo-dev ROI? `[Developer-reported experience]` `[Reasonable inference]`
- **`area_biome_unlocks` (50.0%) & `exploration` (34.1%)**: Hand-crafting large sequential biomes/maps creates a brutal **Content Treadmill**—players consume weeks of solo map building in 20 minutes (`S18`, `S27`).
- **`trading` (25.0%)**: Requires bulletproof atomic server transactions, `PolicyService` `IsPaidItemTradingAllowed` compliance, anti-scam UI, and anti-dupe security—one race-condition dupe destroys the entire economy (*Grow a Garden*, *Pet Sim 99*, *MM2*) (`S08`, `S11`).
- **`boss_battles` (29.5%; 0.0% of Simple-Hits!)**: Well-crafted bosses require complex state machines, telegraphed VFX/animations, scaling HP across variable server sizes, and exploit-proof hitboxes—yet contribute zero differentiation if reduced to standing still and clicking a damage sponge (`S14`).

### 8. Which features deliver disproportionate value for a solo/small development team? `[Strongly supported by evidence]` `[Reasonable inference]`
1. **`visible_player_progression` + `social_recognition`** (Low cost, 95.5%–100% prevalence): Overhead titles, win-streak halos, glowing crafted gear, or visible base pedestals cost hours to script and drive constant social aspiration.
2. **`random_events` + `server_wide_announcements`** (Low cost, 50%–70% viral prevalence): Automated server-wide weather shifts, hazard mutators, or rare-drop banners multiply replayability and clip-sharing across existing maps with zero new 3D terrain.
3. **`cooperation` + `cooperative_objectives`** (Medium cost, **93.3% Sustained prevalence**): Designing a loop where 2–4 friends organically help or rescue each other directly boosts Roblox's official **Intentional Co-Play Days** RFY signal (`S03`) and turns players into content for one another.
4. **Procedural / Modifier-Driven Replayability** (*Tower of Hell*, *Natural Disaster Survival*, *DOORS*, *Dead Rails*): Swapping stage orders, run modifiers, or physics hazards scales playtime exponentially without hand-building new worlds.
5. **Bounded `offline_progression`** (Very Low cost): Simple timestamp-delta calculation (`os.time() - lastLogout`, capped at 8–12h) creates a gentle, youth-safe D1 return greeting with ~20 lines of Luau.

---

## 3. Correlation vs. Causation Audit (Critical Methodological Guardrail)

Section 4 of `Research.txt` warns against confusing feature frequency with causal success. Five confounding factors explain why common features appear in our 44-game dataset without automatically *causing* success `[Reasonable inference]` `[Strongly supported by evidence]`:

1. **Reverse Causality (Scale Pays for Features):** Established giants (*Adopt Me!*, *Blox Fruits*, *Brookhaven*) feature weekly `limited_time_content` (84.1%), `multiple_currencies` (66.7% sustained), and complex `trading` (33.3%) *because* multi-million-dollar DevEx revenue funded 30–100 person LiveOps teams *after* an initial lean loop succeeded—not because launching with 5 currencies caused breakout success (`S24`).
2. **Studio Network & Portfolio Confounding:** In the Viral cohort, `offline_progression` (40%), `tycoon_mechanics` (40%), and `stealing_raiding` (20%) heavily cluster inside **Do Big Studios / Splitting Point / `misfitsbsthree`** titles (*Steal a Brainrot*, *Steal An Egg*, *Grow a Garden*, *Plants vs Brainrots*, *Throw Food For Animals*). Their explosive peaks were heavily amplified by cross-promotion, existing multi-million followings, and coordinated Admin Abuse spectacles—not merely the mechanics in isolation (`S14`, `S24`).
3. **Survivorship Bias on Simple Mechanics:** *Sol's RNG* and *Climb and Jump Tower* prove low-cost loops *can* clear 1B+ visits, while *Garden Horizons* (96% rating, `-99.99%` collapse) and thousands of 0-CCU DevForum template clones (`~2.5%` D1 retention) prove identical mechanics fail >99% of the time without first-mover novelty, crisp execution, or distribution (`S14`, `S27`).
4. **Era & Platform Algorithm Shift:** Legacy mechanics like AFK `idle_passive_progression` worked far better under Roblox's pre-July-2025 Premium Payouts (EBP) and pre-June-2026 7-day discovery window. Today's **60-minute/day RFY playtime cap** and **Active Spender first-3-games Creator Rewards** directly weaken pure AFK loops (`S03`, `S07`).
5. **Metric Confounding (Peak CCU vs. Retention):** Features correlated with massive **peak CCU** (`server_wide_announcements`, `stealing_raiding`, `rebirths_prestige`, `offline_progression`) show **much higher post-peak decay** than features correlated with **durable 28-day retention** (`cooperation`, `achievements`, `meaningful_competition`, `skill_trees`).
