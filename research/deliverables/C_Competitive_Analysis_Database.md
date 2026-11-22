# Deliverable C — Competitive Analysis Database (n = 44 Verified Experiences)

**Collection Date:** `2026-11-22`  
**Machine-Readable Dataset:** [games_database.csv](../data/games_database.csv) (validated via [validate_research_data.py](../scripts/validate_research_data.py))  
**Research Standard:** Strictly zero fabricated metrics. Momentary concurrent user (CCU) snapshots are separated from historical peaks and sustained late-2026 baselines; total lifetime visits are never conflated with current active health. Private Creator Hub telemetry not publicly disclosed by Roblox (exact per-game average session duration, exact 30-day visit deltas, retention curves) is explicitly marked **`Unknown`** unless corroborated by documented third-party estimates (`S11`, `S14`, `S15`).

---

## 1. Cohort Sampling Architecture

To avoid survivorship bias from studying only legacy billion-visit giants, the 44 deduplicated experiences span all **6 required market archetypes** from Section 3 of `Research.txt`:

| Category | Count | Share | Analytical Purpose |
| :--- | ---: | ---: | :--- |
| **1. Established market leaders** | 8 | 18.2% | Map enduring multi-year moats, live-ops standards, and monetization benchmarks. |
| **2. Recently viral games (30–365+ days)** | 10 | 22.7% | Dissect 2025–2026 viral velocity triggers, Admin Abuse peaks, and post-peak survival vs. collapse. |
| **3. Emerging high-growth games** | 7 | 15.9% | Identify rising 2026 momentum and elite peak-to-baseline retention efficiency across genres. |
| **4. Sustainable mid-sized games** | 7 | 15.9% | Prove indie/solo/niche commercial viability without chasing 1M+ CCU viral volatility. |
| **5. Games with declining popularity** | 6 | 13.6% | Diagnose structural decay modes (dupe inflation, P2W fatigue, clone saturation, meme decay, story end). |
| **6. Simple-mechanic disproportionate results** | 6 | 13.6% | Quantify highest visits-per-engineering-hour loops realistic for lean solo developers. |
| **Total Verified Experiences** | **44** | **100.0%** | **All 6 categories populated; 0 duplicates; 100% dated `2026-11-22`.** |

---

## 2. Category 1 — Established Market Leaders (8 Games)

### Quantitative Telemetry (`2026-11-22`)

| ID | Title & Developer | Release | Genre | Late-2026 CCU | Peak CCU (Date) | Visits | Like % | Favorites | Session Avg | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :--- | :--- | :--- |
| **G01** | **Brookhaven RP** *(Wolfpaq / Voldex)* | 2020-04-21 | Town & City / Open-World RP | ~310k–500k+ | 1,296,208 (Dec 2025) | ~89.69B | 85.91% | ~31.11M | Unknown | Medium |
| **G02** | **Blox Fruits** *(Gamer Robot Inc.)* | 2019-01-16 | Anime Action RPG / PvP | ~120k–330k+ | 2,781,531 (Dec 2024) | ~65.6B | 92.31% | ~20.2M | Unknown | High |
| **G03** | **Adopt Me!** *(Uplift Games)* | 2017-07-13 | Pet Collection / Trading / RP | ~230k–260k+ *(Oct pk 1.37M)* | 1,884,171 (Apr 2021) | ~45.47B | 86.4% | ~29.89M | Unknown | High |
| **G04** | **Murder Mystery 2** *(Nikilis)* | 2014-01-17 | Social Deduction / Survival | ~90k–210k+ | ~2,240,000 (Oct 2026) | ~32.35B | 90.79% | ~24.88M | Unknown | Low-Med |
| **G05** | **RIVALS** *(Nosniy Games)* | 2024-05-26 | Competitive Arena FPS | ~110k–200k+ *(30d pk 461.8k)* | 967,342 (Feb 2026) | ~19.4B | 93.6% | ~97.9M | ~12.7–13.5m *(est; off. Unk)* | High |
| **G06** | **The Strongest Battlegrounds** *(Yielding Arts)* | 2022-08-01 | Anime Battlegrounds PvP | ~40k–55k+ *(event ~177.5k)* | ~1,395,000 (Dec 2024) | ~19.68B | 83.7% | ~7.84M | Unknown | High |
| **G07** | **Dress To Impress** *(DTI Group)* | 2023-11-11 | Social Fashion Competition | ~50k–85k+ | 1,743,147 (Dec 2024) | ~11.37B | 90.5% | ~7.8M | Unknown | Med-High |
| **G08** | **DOORS** *(LSPLASH)* | 2022-08-10 | Co-op Procedural Horror | ~20k–50k+ *(event ~274k+)* | 381,720 (Jan 2023) | ~8.04B | 93.06% | ~8.4M | Unknown | High |

### Gameplay, Live-Ops & Commercial Profiles (Category 1)

| ID | Trajectory & Update Cadence | Monetization Stack | Core Loop & Progression | Social Mechanics & DSP |
| :--- | :--- | :--- | :--- | :--- |
| **G01** | Mature unrivaled plateau; weekly/bi-weekly Voldex content drops | Cosmetic/convenience passes (Estates, Vehicles, Music, PentHouse) + seasonal packs | Spawn → free house/car/outfit → open social RP; horizontal expression & secrets | Town sandbox, house perms, Spatial Voice. **DSP:** Zero-friction free hangout. |
| **G02** | Sawtooth plateau; episodic blockbuster updates (Update 30 Sep 2026) | High-ARPU Perm Fruits, 2x passes, Dark Blade, Notifier, rerolls, private servers | Island quests → collect/awaken fruits/weapons → bosses/raids → 3 Seas & bounty PvP | Crews, co-op Sea Events, fruit trading, open PvP. **DSP:** Definitive anime MMO treadmill. |
| **G03** | Resilient 9-yr leader; disciplined weekly updates | Limited legendary pets, Fly/Ride potions, VIP, houses/vehicles, Bucks, event passes | Pet/baby care tasks → Bucks → hatch eggs → Neon/Mega Neon crafting & trading | Massive anti-scam trade economy, family RP. **DSP:** Gold-standard weekly live-ops + pet bond. |
| **G04** | Resurgent 13-yr titan (new 2.24M peak Oct 2026); sparse seasonal updates | Seasonal Godly/Ancient weapon bundles, crate unboxing, Elite/Radio passes, coins | 12-player Murderer/Sheriff/Innocent 2–3 min rounds; Prestige X + Godly/Chroma trading | Bluffing, Spatial Voice, external value-list trading. **DSP:** Timeless 3-min loop + CS:GO trading. |
| **G05** | Compounding FPS leader; structured seasons (Season 4 Nov 2026) | Non-P2W Skin Cases, wraps/charms, Battle Passes, early-access weapon bundles | Step on lobby Duel Pads → first-to-5 1v1–5v5 rounds → Keys, Contracts, streaks, Ranked | Physical duel challenges, squads, crossplay. **DSP:** Cracked mobile/PC/console FPS feel + Duel Pads. |
| **G06** | Mature plateau + event spikes; periodic character drops (1–4 mo) | Early Access passes, Private Servers+ (admin/boss/build), kill sounds/emotes | Open FFA/duels → M1/dash/ability combos → charge cinematic Awakening finisher | FFA rivalries, duels, clan wars, creator sandboxes. **DSP:** Fluid non-P2W Battlegrounds benchmark. |
| **G07** | Post-viral durable mainstream (3rd anniv Nov 2026); high-velocity weekly/seasonal | VIP wardrobe, Custom Makeup, Speed, Item Limit, Cash packs, pose bundles | 5–6 min themed styling → runway walk → live 1–5 star peer voting; Star rank ladder | Peer voting, duo runway, TikTok outfit sharing, lore quests. **DSP:** High-fashion rigs + competitive runway. |
| **G08** | Episodic flagship (*The Hollow* Oct 2026); major multi-month floors/chapters | Revive tokens, Knobs, pre-run gear, event passes/skins, private servers | 1–4p elevator → 100 procedural rooms countering entity audio/visual tells; Modifiers & badges | Co-op closet/light sharing, Spatial Voice scares. **DSP:** Indie-grade horror craft & roguelite learning. |

---

## 3. Category 2 — Recently Viral Games (10 Games, Past 30–365+ Days)

### Quantitative Telemetry (`2026-11-22`)

| ID | Title & Developer | Release | Genre | Late-2026 CCU | Peak CCU (Date) | Visits | Like % | Trajectory | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :--- | :--- |
| **G09** | **Steal a Brainrot** *(BRAZILIAN SPYDER + Do Big)* | 2025-05-15 | Meme PvP Base-Raiding Tycoon | ~50k–53k | **25,800,000** (Oct 2025) | ~74.51B | 85.11% | Normalized -99.8% to strong tail | Low-Med |
| **G10** | **Steal An Egg** *(misfitsbsthree / Do Big affil.)* | 2026-07-24 | Extraction-Treadmill Pet Raider | **~800k–1M+ (pks)** | **14,300,000** (Sep 2026) | ~11.6–11.7B+ | 91.0% | Active late-2026 #1 apex | Low-Med |
| **G11** | **99 Nights in the Forest** *(Grandma's Fav. Games)* | 2025-03-03 | Co-op Survival Horror Roguelike | **~120k–204k** | **14,200,000** (2025) | ~30.61B | 90.51% | Sustainable top-tier juggernaut | Med-High |
| **G12** | **Plants vs Brainrots** *(Splitting Point / Jandel)* | 2025-07-31 | Meme TD / Idle Tycoon Hybrid | ~1.5k–3.1k | **8,650,000** (Oct 2025) | ~4.73B | 94.77% | Flash-in-the-pan collapse (-99.96%) | Low-Med |
| **G13** | **Fish It!** *(Fish Atelier)* | 2024-10-20 | Arcade Incremental Fishing RPG | **~65k–81k** | **2,710,000** (Dec 2025) | ~4.8B+ | 82.8% | Sustainable casual fishing leader | Low-Med |
| **G14** | **Throw Food For Animals** *(Goofy Chupacabra / misfitsbsthree)* | 2026-09-18 | Hyper-Casual Throw-Distance Sim | ~20k–200k+ (pks) | **2,448,726** (Fall 2026) | ~382M+ | 94.0% | Active 2-mo breakout (unproven 2027) | Low-Med |
| **G15** | **Dead Rails** *(RCM Games)* | 2025-01-01 | Co-op Physics Train Survival | ~15k–35k *(pk 64k)* | **1,476,198** (Apr 2025) | ~6.67B | 92.54% | Post-peak plateau (update burnout) | Medium |
| **G16** | **Forsaken** *(Forsaken Dev Team)* | 2024-07-27 | Asymmetrical 1vMany Horror | ~50k–54k *(wk 98k)* | **1,221,080** (Late 2025) | ~5.97B | 84.4% | Sustainable fandom-anchored hit | Med-High |
| **G17** | **Blue Lock: Rivals** *(Miro & Do Big / orig. Chrollo)* | 2024-11 | Anime 5v5 Sports + Gacha | ~10k–14k *(wk 66k)* | **1,097,082** (Mar 2025) | ~5.0B+ | 96.6% | Update-cyclical sports niche | Med-High |
| **G18** | **Ink Game** *(games i think)* | 2024-12 | Elimination Survival Minigames | Unknown *(active tail)* | **810,470** (Aug 2025) | ~3.4B | Unknown | Post-2025 viral wave tapering | Medium |

*(Favorites & Avg Session Duration are `Unknown` for G09–G18 except G15 Dead Rails Favorites ~6.20M; full 18-field records stored in [games_database.csv](../data/games_database.csv).)*

### Gameplay, Monetization & Strategic Highlights (Category 2)
- **G09 (*Steal a Brainrot*):** Conveyor meme purchase → passive cash → lock base & raid rivals → Rebirth (19 tiers). Monetizes grief-avoidance via **Private Servers** + slap/luck/cash passes + weekly Admin Abuse.
- **G10 (*Steal An Egg*):** Treadmill speed training → snatch eggs from NPC nests/rival bases → hatch passive-income mutated pets → biome unlocks & Rebirths. Driven by Do Big affiliation + *Sammy Is Coming* crossover.
- **G11 (*99 Nights in the Forest*):** Daytime scavenge/craft → expand Campfire → defend against wolves/cultists/The Deer to Night 99 → earn/buy Diamonds for 20+ specialized classes. Built by veteran *Break In* trio.
- **G12 (*Plants vs Brainrots*):** Plant lane defense vs Brainrot waves → passive cash → Rebirth (+50% Luck). Proves even Jandel's portfolio collapses `-99.96%` when depth is shallow.
- **G13 (*Fish It!*):** Fast tap-bar arcade fishing → 8 rarity tiers + mutations → Rods/boats/islands. Captured massive mobile casual demand during *Fisch*'s monetization controversy.
- **G14 (*Throw Food For Animals*):** Pull-up bar Throw Power → fling food across distance biomes → capture quirky animals for offline base cash. Owned by `misfitsbsthree` (same owner as *Steal An Egg*!).
- **G15 (*Dead Rails*):** 3–4p co-op Western zombie train survival with slapstick 3D physics (shoving zombie corpses into boiler as fuel). Fair Treasury Bonds monetization; cooled due to indie team burnout.
- **G16 (*Forsaken*):** Classic Roblox mythos 1vMany chase horror + ARG puzzles. Sustained 50k–98k CCU despite severe internal ownership drama due to fandom/skin loyalty.
- **G17 (*Blue Lock: Rivals*):** 5v5 anime egoist soccer + Style/Flow gacha balanced by generous Saturday free Lucky Spin codes (96.6% rating).
- **G18 (*Ink Game*):** Multi-round survival elimination minigames (*Red Light*, *Glass Bridge*) riding global survival pop culture.

---

## 4. Category 3 — Emerging High-Growth Games (7 Games)

| ID | Title & Developer | Release | Genre | Late-2026 CCU | Peak CCU | Visits | Like % | Key Growth & Retention Signal | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :--- | :--- |
| **G19** | **The Forge** *(Peak Dev Studios)* | 2025-05-09 | Mining / Blacksmithing RPG | ~17k–34k | 1,051,531 | ~1.06B | 94.45% | Combinatorial ore-smithing minigame + YouTube build-recipe search pull | Med-High |
| **G20** | **Volleyball Legends** *(Volleyball Game Group)* | 2024-12-16 | Competitive 6v6 Anime Sports | ~34k–51k+ | 435,775 | ~4.03–4.15B | 95.17% | Outperforms soccer rivals on daily floor; minimal high-polish rivals | Med-High |
| **G21** | **Violence District** *(Cerealboii)* | 2024-10-30 | 5v1 Asymmetrical Horror | ~50k–70k+ | 277,693 | ~1.74B | 92.9% | Holds **18%–25% of peak CCU** via tactical ranged stun kits & weekly drops | Med-High |
| **G22** | **Climb For Animals Eggs** *(100% GRIND!)* | 2026-09-06 | Vertical Climb & Egg Tycoon | ~9.9k–20k | 166,946 | ~102M+ | **98.6%** | Smart late-2026 fusion (treadmill/egg offline tycoon + vertical climb) | Low-Med |
| **G23** | **Cat Battles** *(Cute Malt / Incubator)* | 2026-09 | Server-Auth Physics Sumo | ~1.7k–5.5k | 100,144 | ~128.6M | 73.27% | Roblox Creator Incubator physics showcase; early retention/gacha friction | Med-High |
| **G24** | **Illegal Soccer** *(Repotted)* | 2026-05-11 | Chaotic Armed Arcade Sports | **~33k–35k** | 81,522 | ~347M | 86.56% | **>40% peak-to-baseline CCU ratio** — elite zero-P2W cosmetic breakout | Medium |
| **G25** | **Dandy's World** *(BlushCrunch / Qwelver)* | 2024-01-25 | Co-op Mascot-Horror Extraction | **~113k–191k** | 866,577 | ~8.01B | Unknown | Compounding breakout (Nov 2026 1.0 surge); deep Distractor/Extractor roles | Med-High |

---

## 5. Category 4 — Sustainable Mid-Sized Games (7 Games)

| ID | Title & Developer | Release | Genre | Late-2026 CCU | Peak CCU (Date) | Visits | Like % | Longevity & Commercial Lesson | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :--- | :--- |
| **G26** | **Bee Swarm Simulator** *(Onett — Solo)* | 2018-03-21 | Resource / Swarm Sim | ~40k–48k+ | 264,505 (Dec 2025) | ~4.68B | **95.6%** | **Solo dev** sustaining 40k+ CCU for 8.5 yrs on ~1 update/yr via deep systems + fair monetization | Med-High |
| **G27** | **Tower of Hell** *(YXCeptional)* | 2018-06-18 | Procedural Obby | ~23k+ *(30d 49.3k)* | 170,829 (Sep 2020) | ~29.47B | 73.65% | Procedural randomization + zero checkpoints + paid server mutators = infinite replayability | Low-Med |
| **G28** | **Welcome to Bloxburg** *(Coeptus / Coffee Stain)* | 2014-11 *(F2P Jun 24)* | Architecture / Life Sim | ~11k–18k *(30d 41.9k)* | 592,451 (Jun 2025) | ~10.17B | 88.5% | ~23–25 min est. sessions; high willingness-to-pay for builder passes | High |
| **G29** | **Natural Disaster Survival** *(Stickmasterluke)* | 2011-12 | Physics Round Survival | ~8k–10.6k+ | 128,661 (Mar 2025) | ~4.56B | 90.78% | Zero-tutorial 2-min physics comedy survives 15+ yrs with near-zero live-ops | **Low** |
| **G30** | **Work at a Pizza Place** *(Dued1)* | 2008-03 | Co-op Job Sim / Town RP | ~2.5k–5k *(Oct 8.6k)* | **168,033 (Sep 2026)** | ~5.63B | 92.9% | Hit all-time CCU peak 18.5 yrs post-launch (*Roblox 20*); interdependent roles endure | Low-Med |
| **G31** | **Theme Park Tycoon 2** *(Den_S)* | 2012-01-02 | Sandbox Construction Tycoon | ~2.4k–3.5k *(pk 6k)* | 57,962 (Jul 2024) | ~1.63B | 89.0% | Deep authentic coaster engineering sustains loyal creative builders for 14+ yrs | High |
| **G32** | **Deepwoken** *(Monad Studios East)* | 2021-12 | Paid-Access Soulslike RPG | ~2.8k–5.3k | 62,422 (Dec 2022) | ~1.66B | 86.22% | **400 R$ Paid Access** + 1.66B visits proves high-ARPU 13+/18+ niches beat CCU vanity | High |

---

## 6. Category 5 — Games with Declining Popularity (6 Games)

| ID | Title & Developer | Release | Genre | Late-2026 CCU | Peak CCU (Date) | Peak Drop | Visits | Like % | Primary Verified Decay Root Cause |
| :--- | :--- | :--- | :--- | :--- | :--- | :-: | :--- | :-: | :--- |
| **G33** | **Grow a Garden** *(BMWLux / Splitting Point / Do Big)* | 2025-03-26 | Cozy Idle Farming Sim | ~13k–25k *(24h 68k)* | 22,375,597 (Aug 2025) | **-99.9%** | ~36.03B | 90.0% | Pet-duping economy crash, P2W friction, reskin burnout, Admin War normalization |
| **G34** | **Anime Defenders** *(Small World Games)* | 2024-04 | Anime Gacha TD | ~100–250 | 377,836 (Jul 2024) | **-99.95%** | ~3.44B | 96.7% | Punishing gacha RNG, anti-alt CAPTCHA backlash, red-ocean TD clones, unlicensed IP risk |
| **G35** | **Piggy** *(MiniToon)* | 2020-01-28 | Episodic Escape Horror | ~2k–7k+ | 533,409 (May 2020) | **-99.1%** | ~14.47B | 90.3% | Main storyline conclusion (Book 2 ended) + creator pivot to spin-offs |
| **G36** | **Jailbreak** *(Badimo)* | 2017-04-21 | Open-World Cops & Robbers | ~10k+ *(30d 25k)* | 530,399 (Apr 2020) | **-97.0%** | ~8.09B | 87.7% | Feature bloat, legacy gamepass saturation, cadence slowdown (stabilized via AIP/Seasons) |
| **G37** | **Pet Simulator 99!** *(BIG Games)* | 2023-11-30 | Pet Hatching / Trading Sim | ~31k–42k+ | 732,936 (Dec 2023) | **-95.0%** | ~2.72B | 94.7% | Acute P2W monetization fatigue, lottery pet alienation, AFK burnout, newer idle rivals |
| **G38** | **Toilet Tower Defense** *(Telanthric Dev)* | 2023-06 | Meme-IP Gacha TD | ~15k–40k *(Nov 66k)* | 522,376 (Mar 2024) | **-94.0%** | ~6.23B | 85.6% | Waning *Skibidi Toilet* meme shelf-life + 2025–2026 update droughts (partial Nov revival) |

---

## 7. Category 6 — Simple-Mechanic Disproportionate Results (6 Games)

| ID | Title & Developer | Release | Genre | Late-2026 CCU | Peak CCU (Date) | Visits | Like % | Why Results Outpaced Build Complexity | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :--- | :--- |
| **G39** | **Fisch** *(WoozyNate)* | 2024-10-05 | Cozy Fishing RPG | ~40k–70k+ | 1,273,618 (Oct 2025) | ~5.16B | 90.84% | **Solo-dev launch** built on 1 crisp 2D tension-bar minigame + clean stylized art + trust-first comeback | Low-Med |
| **G40** | **A Dusty Trip** *(Splitting Point)* | 2024-02-15 | Co-op Physics Driving | ~13k–18k+ | 572,612 (May 2024) | ~2.64B | 90.02% | Minimal procedural desert + weld-physics car parts generated infinite slapstick co-op clips | Low-Med |
| **G41** | **Don't Wake the Brainrots!** *(Slime Vine)* | 2025-08-08 | Stealth Snatch-and-Run | ~20–45 | 521,500 (Oct 2025) | ~412M+ | 82.5% | Single arena + proximity aggro AI hit 521k peak at meme zenith before collapsing -99.99% | **Low** |
| **G42** | **Sol's RNG** *(YGvw_Sol)* | 2023-12-02 | Pure Single-Button Idle | ~35k–40k+ | 193,800 (May 2024) | ~2.31B | 91.43% | Zero combat/levels—just Roll button + dazzling Aura VFX/music + group-join Auto-Roll hack | **Low** |
| **G43** | **Build A Plane** *(Budget Gaming)* | 2025-06-01 | Voxel Aircraft Builder | ~2.6k–4.6k+ | 186,394 (Aug 2025) | ~788M | 85.5% | Grid-snapping block physics + procedural flight corridor + offline cash = 788M visits on lean team | Low-Med |
| **G44** | **Climb and Jump Tower** *(Climbing World)* | 2025-04-01 | Vertical Landmark Climb | ~2.3k+ | 113,851 (Jun 2025) | ~1.14B | **97.25%** | Climb speed + freefall coin rain + standard pets = **1.14B visits** on ultra-lean 1–3 dev scope | **Low** |

---

## 8. Key Database Takeaways

1. **Lifetime Visits ≠ Live Commercial Health `[Officially confirmed / Observational correlation]`:** *Grow a Garden* (36.03B visits) and *Piggy* (14.47B visits) hold more lifetime visits than *Illegal Soccer* (347M) or *Violence District* (1.74B), yet the newer, tighter loops match or beat them in active late-2026 CCU and peak-retention ratio.
2. **Approval Ratios Don't Guarantee Survival `[Strongly supported by evidence]`:** *Anime Defenders* (96.7%), *Pet Simulator 99!* (94.7%), and *Plants vs Brainrots* (94.77%) all sit above 94% positive ratings while suffering 95%–99.96% CCU drops—whereas *Tower of Hell* (73.65%) sustains 23k–49k CCU eight years post-launch.
3. **Solo-Scale Leverage Is Real—With One Catch `[Strongly supported by evidence]`:** *Bee Swarm Simulator* (Onett), *Fisch* (WoozyNate), *Sol's RNG* (YGvw_Sol), *Natural Disaster Survival* (Stickmasterluke), and *Climb and Jump Tower* prove 1–3 developers can reach 1B–5B+ visits—*provided* they build **high-leverage core mechanics** rather than trying to out-asset 50-person RPG studios.
