# Deliverable I — Alternative Game Concepts (6 Market-Backed Concepts × 20 Specs)

**Collection Date:** `2026-11-22`  
**Research Scope:** Section 14 of `Research.txt` — Six original, solo-feasible Roblox game concepts grounded directly in late-2026 market evidence (covering all 5 mandatory archetypes plus 1 underserved cozy-crafting wildcard). Every concept is engineered from day one for:
- **1-CCU Cold-Start Viability** (100% fun solo or with bot/dynamic scaling — never empty-lobby dead)
- **80% Mobile Ergonomics** (`<2GB` Android RAM budget, thumb-friendly 2-button controls)
- **Jan 2026 Age-Gated Chat Resilience** (visual signifiers & non-verbal ping wheels)
- **March 2026 Paid Random Items Safety** (zero Robux-bought RNG or Paid Luck Boosts → globally playable in UK/AU/BR/BE/NL without legal friction)
- **R15 Avatar Compliance** (eligible for the **`$0.0054/R$` U.S. 18+ DevEx tier**)

---

## Concept Architectural Snapshot

| ID | Working Title | Section 14 Archetype | Core Genre Hybrid | 1-CCU Viable? | Est. Solo MVP Build | Baseline Score (Deliv. J) |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: |
| **C1** | **Orbstrike: Boss Rush** | Improved Existing Concept | Arcade Dodgeball Boss Rush + Active Orb-Eggs | Yes (1–4p scaling) | 5–7 weeks | `6.95 / 10` (#6) |
| **C2** | **Egg Heist: Boss Vault** | Significantly Reimagined Concept | PvE Co-Op Boss Extraction + Utility Orbs + Offline Vault Hub | Yes (1–4p scaling) | 4–6 weeks | **`8.43 / 10` (#1)** |
| **C3** | **Curve Clash: Duel Pads** | Simplified Low-Cost Solo Alt | Physical Duel-Pad Trick-Shot Dodgeball PvP + Bot Pad | Yes (AI Duel Bot) | **2–4 weeks** | `8.20 / 10` (#3; **#1 Feasibility**) |
| **C4** | **12-Minute Outpost** | Emerging Market Opportunity | Bite-Sized Co-Op Survival Extraction Roguelike | Yes (1–4p scaling) | 5–8 weeks | `8.30 / 10` (#2; **#1 Sustainability**) |
| **C5** | **Chaos Kitchen: Throw & Serve** | Strong Viral & Social Potential | *Overcooked*-Style Physics Throw Co-Op Roguelite | Yes (1–4p scaling) | 4–6 weeks | `7.98 / 10` (#4; **#2 Organic Growth**) |
| **C6** | **Relic Forge: Magnet Salvage** | Bonus Cozy-Crafting Wildcard | 5s Tension-Bar Magnet Salvage + 3-Relic Combinatorial Forging | Yes (Solo/Social Hub) | 4–6 weeks | `7.85 / 10` (#5) |

---

## Concept C1 — *Orbstrike: Boss Rush* (Improved Version of `GameIdea.txt`)

1. **Working Title:** *Orbstrike: Boss Rush*
2. **One-Sentence Pitch:** Throw, curve, and dodge through instant player-triggered co-op boss arenas where boss-dropped elemental Orb-Eggs hatch into active trick-shot ball abilities and autonomous attack wingmen.
3. **Target Audience:** 10–18 arcade action, simulator-graduate, and boss-rush players across mobile and PC.
4. **Market Opportunity:** Upgrades the familiar boss-and-egg grammar into kinetic arcade action without 5-minute dead waits or multi-biome bloat.
5. **Main Gameplay Hook:** Instant-trigger boss arenas where hatched elemental Orb-Eggs physically change *how* your ball flies (Boomerang, Chain-Lightning Ricochet, Gravity Vortex, Split-Shot).
6. **Core Gameplay Loop:** Step onto Boss Summon Pad (instant 1–4p start) → move, dodge telegraphed AoEs, and throw curved charged orbs at boss weak spots → shatter boss → collect **100% gameplay-earned** elemental Orb-Egg → hatch into active ball ability/wingman → challenge higher Threat Tier with dynamic arena mutators.
7. **First Five Minutes of Gameplay:** Spawn facing a glowing Tier-1 Training Dummy that shatters in 3 curved throws (0–25s) → step straight onto the Tier-1 Slime Golem Summon Pad (30s) → dodge 2 clear red floor slams, defeat boss (2m) → crack earned Ember Orb-Egg immediately equipping a flaming Ricochet Ball (3m) → test Ricochet on Tier-2 Boss or optional 30-second Moving-Target Arcade Challenge (4–5m).
8. **Progression System:** Threat Tiers 1–10 inside 1 modular transforming arena (lighting/hazards shift per tier); Orb-Core Codex (24 active abilities + mutations); mastery badges unlocking orb fusion slots.
9. **Social Mechanics:** 1–4 player co-op Boss Summon Pads (HP scales dynamically), synced elemental combos (Frost + Lightning = Shatter burst), non-verbal ping wheel (*"Stagger!"*, *"Revive!"*), shared lobby leaderboard statues.
10. **Viral Growth Mechanisms:** Flashy multi-bounce ricochet boss-finish clips auto-captured via **Video Captures API** for Roblox Moments; friend co-op carry/combo invites (`Player.PartyId`).
11. **Retention Strategy:** Rotating daily Arena Mutators (Low Gravity, Double Boss, Rapid Charge), visual Orb Codex silhouettes, weekly Threat Tier boss-speedrun leaderboards.
12. **Monetization Opportunities:** Strictly non-RNG: extra Orb Loadout Slots pass, cosmetic Orb Trails & Shatter VFX, 2x Mastery Shards pass, mid-fight Co-Op Revive Dev Product, Private Servers (Roblox Plus eligible).
13. **Primary Competitors:** *Blade Ball*, *Death Ball*, *Boss Fighting Stages*, *Blox Fruits* raids.
14. **Competitive Differentiation:** Replaces click-spamming stat sponges with mobile-friendly active dodging and trick-shot ball physics where hatched eggs unlock *mechanics*, not passive damage multipliers.
15. **MVP Features:** 1 modular transforming arena, 3 distinct telegraphed bosses + 4 arena mutators, active curve-throw + dodge controller, 12 hatchable active Orb-Cores (earned-only), 1–4p Summon Pad, Codex UI.
16. **Estimated Development Complexity:** **Medium** (core engineering spent on responsive boss state machines, telegraphs, and projectile hitreg).
17. **Content Production Requirements:** **Moderate** — 1 modular arena avoids multi-biome bloat, though players eventually crave new boss archetypes every 3–4 weeks.
18. **Major Risks:** Boss AI feeling repetitive after 10 clears; projectile hitreg desync on high-ping mobile devices; lower viral comedy hook than extraction or chaos loops.
19. **Assumptions Requiring Validation:** That mobile players enjoy dodging + aiming curves simultaneously, and that active Orb abilities feel meaningfully distinct.
20. **Proposed Prototype Experiments:** Build 1 greybox boss + 3 active Orb abilities in 10 days; measure `<60s` bounce, clear rate, and voluntary rematch count across 25 Discord/mobile testers.

---

## Concept C2 — *Egg Heist: Boss Vault* (Significantly Reimagined Version of `GameIdea.txt`) — **Baseline #1 Ranked**

1. **Working Title:** *Egg Heist: Boss Vault*
2. **One-Sentence Pitch:** A 1–4 player PvE boss-heist extraction roguelike where you dodge patrolling mega-bosses, launch stun-orbs to crack their vault, snatch rare glowing eggs, and sprint to the exit before the vault collapses.
3. **Target Audience:** 9–20 casual-to-core mobile & PC players who love *Steal An Egg*'s heist thrill and *99 Nights* / *Dead Rails* co-op runs—without toxic public-server PvP griefing.
4. **Market Opportunity:** Captures the convergence of late-2026's #1 viral hit (*Steal An Egg*, 14.3M peak, `S14`) and 2026's highest-retention breakout genre (co-op survival extraction: *99 Nights* 120k–204k CCU, *Dandy's World* 113k–191k, `S14`), solving the #1 complaint of "Steal a..." games (griefing rage-quits).
5. **Main Gameplay Hook:** **Push-your-luck PvE Boss Heist** — hurl utility orbs (Decoy, Freeze, Boomerang, Grapple) to outsmart a patrolling giant Boss, grab heavy glowing eggs that slow your sprint, and decide whether to extract safely OR push one vault chamber deeper for Mythic mutated eggs!
6. **Core Gameplay Loop:** Grab utility orb loadout in personal Vault Hub → step into instant 1–4p Vault Elevator (0-second wait!) → sneak/dodge patrolling Boss & traps → throw utility orbs to distract/stun Boss and crack Egg Pedestals → carry heavy glowing egg(s) back to Extraction Pad (or risk Chamber 2/3 for multiplied rarity!) → hatch **100% earned** Vault Guardians displaying physically in your Hub → collect bounded 12-hour offline Vault Cash to upgrade orb gadgets & hub decor.
7. **First Five Minutes of Gameplay:** Spawn inside bright personal Vault Hub overlooking the giant glowing Boss Vault door (0–10s) → follow floor beam to pick up free **Decoy Orb** and enter Chamber 1 (15s) → toss Decoy Orb to lure lumbering Vault Guardian aside, grab glowing Rare Egg, sprint through closing laser gate onto Extraction Pad (45–90s!) → egg cracks in Hub into a cute glowing *Ember Beetle* generating coins on pedestal (2m) → equip **Freeze Orb** and launch Chamber 1→2 double-depth heist (3–5m).
8. **Progression System:** Chamber Depth tiers (Chambers 1–5 with procedural trap/boss mutators); 6 throwable Utility Orb gadgets + upgrades; **Vault Guardian Codex** (sizes + visual mutations: Cracked, Golden, Storm-Charged); customizable personal Vault Hub display pedestals with capped 12h offline income.
9. **Social Mechanics:** **Zero-chat-needed co-op heist roles** (Distractor lures boss with Decoy Orb, Stunner lands Freeze Orb, Carrier hauls heavy Mythic Egg, Reviver rescues downed allies) supported by a 4-icon non-verbal Ping Wheel (`"Distract!"`, `"Freeze Now!"`, `"Extract!"`, `"Help!"`), native `Player.PartyId` elevator squads, +10% friend haul bonus (capped 3 friends), and visitable neighbor Vault Hubs for flexing rare hatches.
10. **Viral Growth Mechanisms:** Built-in **15-second Roblox Moments gold**—sprinting for the closing extraction gate at 1 HP carrying a towering Golden Mythic Egg while a giant boss lunges behind you and a friend saves you with a clutch Freeze Orb! Auto-prompt **Video Captures API** on close-call extractions; *"Solo Depth-5 Vault Heist!"* YouTube/TikTok challenge hooks.
11. **Retention Strategy:** Overlapping retention horizons: immediate 90-second heist loop (`<60s` bounce killer) → 10–15m multi-chamber greedy runs (P90 session length & Creator Rewards 10m bar) → **bounded 12h offline Vault income** (gentle non-punitive D1 check-in!) → automated hourly **Vault Storm** mutation modifiers & weekly Experience Events (`D7–D28 Play Days`).
12. **Monetization Opportunities:** **100% Paid Random Items Exempt** (eggs are strictly gameplay-extracted, ZERO Robux currency conversion, ZERO paid Luck Boosts!). Ethical, high-converting stack: Extra Vault Display Pedestal Passes (`+4/+8 slots`), Extra Orb Utility Belt Slot, Cosmetic Orb Skins/Trails & Hub Themes, Mid-Heist Emergency Revive / Safe-Drop Insurance (1x per run Dev Product), **$2.99/mo (or 199 R$/mo) Vault VIP Club Subscription (100% creator share Month 2+!)**, Private Servers (Roblox Plus eligible), and post-2k MAU safe-state **Rewarded Video** ("Watch ad to double Hub offline collection once/day").
13. **Primary Competitors:** *Steal An Egg*, *99 Nights in the Forest*, *Dandy's World*, *Don't Wake the Brainrots!*, *Dead Rails*.
14. **Competitive Differentiation:** Delivers the adrenaline rush of *Steal An Egg* + tactical teamwork of *Dandy's World* + kinetic throwable orbs—with **zero toxic PvP stealing**, **zero 5-minute waiting timers**, **zero multi-biome art bloat**, and **zero Paid Random Items country blocks**.
15. **MVP Features:** Personal Vault Hub (8 display pedestals + capped 12h offline income), instant 1–4p Vault Elevator, 3 modular Chambers with dynamic lighting/trap swaps, 2 distinct patrolling Boss AIs, 3 throwable Utility Orbs (Decoy, Freeze, Dash-Bomb), heavy-egg carry/extraction mechanic, 20 earned Guardian hatches + 3 visual mutations, 4-icon non-verbal Ping Wheel.
16. **Estimated Development Complexity:** **Low–Medium** (modular square vault chambers, simple sight-cone/sound-aggro boss AI, clean projectile throws, straightforward pedestal DataStore via `ProfileStore`).
17. **Content Production Requirements:** **Low (Systems-Driven)** — Adding 1 new Utility Orb, 1 new Trap Mutator, or 1 new Boss AI immediately multiplies replayability across all existing Vault Chambers without building sprawling new worlds.
18. **Major Risks:** Boss patrol AI getting stuck on geometry or feeling too easy/cheesable; offline Hub income inflating economy if uncapped (mitigated by strict 12h cap + cosmetic/gadget sinks); competing for search share against *Steal An Egg* (mitigated by crisp original visual branding & co-op Vault identity).
19. **Assumptions Requiring Validation:** (a) Players find PvE boss chases tense and funny without player-vs-player stealing; (b) Carrying a speed-reducing glowing egg creates real push-your-luck excitement; (c) 12h capped offline Vault income boosts D1 return without reducing active session length below 10 min.
20. **Proposed Prototype Experiments:** **10-Day Vertical Slice Test** — 1 Hub, 1 Chamber, 1 Boss, Decoy + Freeze Orb, 3 Eggs. Measure `<60s` onboarding completion (target >70%), voluntary 2nd heist start rate (target >60%), avg session length (target ≥10m), and clip-worthiness during 20–30 live Discord playtester runs.

---

## Concept C3 — *Curve Clash: Duel Pads* (Simplified, Low-Development-Cost Solo Alternative) — **#1 Feasibility Priority**

1. **Working Title:** *Curve Clash: Duel Pads*
2. **One-Sentence Pitch:** Step onto instant physical lobby Duel Pads for 90-second trick-shot dodgeball battles with wild physics curves, clutch deflects, and public win-streak halos.
3. **Target Audience:** 11–24 competitive mobile, PC, and console players (*RIVALS*, *Blade Ball*, *Illegal Soccer* demographics—including strong U.S. 18+ spenders eligible for **`$0.0054/R$` DevEx**!).
4. **Market Opportunity:** Combines *RIVALS*' proven instant Duel-Pad architecture (110k–200k CCU, 19.4B visits) and *Illegal Soccer*'s elite `>40%` peak-to-baseline retention with **mobile-friendly curved projectile combat** that eliminates mobile-vs-PC hitscan aiming disadvantages.
5. **Main Gameplay Hook:** Zero-menu physical **Duel Pads** (1v1, 2v2, and an instant **Bot Practice Pad** for 1-CCU cold start) + satisfying swipe/thumb curved throws and last-millisecond **Parry-Catch Counters**.
6. **Core Gameplay Loop:** Spawn in compact stylized court lobby → walk onto glowing 1v1 / 2v2 / AI-Bot Duel Pad (5-second countdown) → fast first-to-5-points arena duel curving/bouncing/catching dodgeballs → earn Trophies, Keys, and visible floating Win-Streak Halo → unlock cosmetic ball skins, curve trails, KO explosions, and climb Ranked divisions.
7. **First Five Minutes of Gameplay:** Spawn right beside an active 1v1 Bot Warm-Up Pad & live player Duel Pads (0–10s) → play a snappy 45-second first-to-3 warm-up duel learning Throw, Curve, and Catch-Counter (10–60s) → win starter Keys & step onto a live 1v1 or 2v2 Duel Pad (1–3m) → finish full competitive duel and immediately hit Rematch or buy first cosmetic Trail (3–5m).
8. **Progression System:** Daily/Weekly Skill Contracts (e.g., *"Land 5 Curve KOs"*, *"Catch 3 Balls"*), public Win-Streak Halo tiers (5/10/25/50+ flames), seasonal Ranked Divisions, and purely cosmetic Ball/Trail/Finisher catalog.
9. **Social Mechanics:** Visible lobby rivalries (*"1v1 me on Pad 2!"*), spectating high-streak duels from elevated court bleachers, 2v2 friend squads (`Player.PartyId`), non-verbal quick-taunt/GG emotes, and seasonal friend-only leaderboards.
10. **Viral Growth Mechanisms:** *"Snapping a 100 Win-Streak with an Insane Curve Shot!"* YouTube/TikTok/Moments clips; auto-trigger **Video Captures API** on match-point deflect KOs; ultra-clean 3-second mute readability for Home Auto-Play Videos.
11. **Retention Strategy:** Pure intrinsic mechanical skill ceiling (highest D30 retention cohort in our 44-game dataset!), win-streak loss aversion, rotating weekly Arena Mutators (Multi-Ball, Bouncy Walls, Low Gravity), and seasonal Ranked resets.
12. **Monetization Opportunities:** **100% Zero-P2W Ethical Cosmetic Stack** (protects 90%+ rating like *RIVALS* & *Illegal Soccer*): Direct-Purchase Ball Skins/Trails/KO Finishers (avoiding lootbox regional bans completely!), Seasonal Cosmetic Pass (earnable + premium track), Private Tournament Servers (Roblox Plus eligible), VIP Club Subscription (100% Mo 2+ share), and high U.S. 18+ `$0.0054` DevEx lift.
13. **Primary Competitors:** *RIVALS*, *Blade Ball*, *Death Ball*, *Illegal Soccer*, *Cat Battles*.
14. **Competitive Differentiation:** Faster to master on mobile than FPS shooters (*RIVALS*), more spatial/tactical positioning than auto-homing single-button deflection (*Blade Ball*), and built cleanly for R15 Server Authority.
15. **MVP Features:** 1 compact court lobby with 4 Duel Pads (1v1, 2v2, Bot Pad, Mutator Pad), 3 minimalist arenas (Standard, Pillar Bounce, Shrinking Floor), 1 server-authoritative Throw/Curve/Catch controller, Win-Streak Halo display, Daily Contracts, 15 direct-buy cosmetic items.
16. **Estimated Development Complexity:** **Very Low–Low (Fastest Solo MVP: 2–4 Weeks!)** — Minimal 3D asset load; 90% of effort goes into making the single throw/curve/catch mechanic feel *incredible*.
17. **Content Production Requirements:** **Near-Zero Treadmill** — Players *are* the content; solo dev maintains balance, cosmetic drops, and occasional arena mutators.
18. **Major Risks:** High-ping mobile catch-timing frustration (mitigate via generous server lag-compensation windows + client visual prediction); matchmaking skill gap crushing newbies (mitigate via ELO-light lobby pads + rewarding Bot Duel Contracts); lower casual `<10` appeal than pet/egg games.
19. **Assumptions Requiring Validation:** That curve-throwing + catch-parrying feels responsive across 80–150ms mobile ping, and that newcomers win/enjoy enough early matches to trigger voluntary rematches.
20. **Proposed Prototype Experiments:** **7-Day Combat Feel Sprint** — 1 arena + 1 Bot + 1v1 pad. Test on both PC and a budget Android phone with 20 testers; gate on ≥5 matches per session and >40% rematch rate.

---

## Concept C4 — *12-Minute Outpost* (Emerging Market Opportunity Concept) — **#1 Sustainability Priority**

1. **Working Title:** *12-Minute Outpost*
2. **One-Sentence Pitch:** A bite-sized 12-minute co-op survival extraction roguelike where 1–4 friends fortify a mobile beacon, throw physics gadgets to hold off escalating waves, and vote whether to extract safely or risk Overdrive.
3. **Target Audience:** 11–24 mobile & PC co-op squads who love *99 Nights in the Forest* and *Dead Rails* but want complete, thrilling runs inside a 10–15 minute break.
4. **Market Opportunity:** Directly addresses **Opportunity 1 (8.4/10)** — 2026's highest-retention genre (*99 Nights* 120k–204k CCU, *Dandy's World* 113k–191k) underserved in the 10–15 minute mobile session sweet spot (`GameAnalytics P90 = 14.7 min`, Creator Rewards `≥10 min`).
5. **Main Gameplay Hook:** **The Minute-8 Extraction Vote** — after surviving 4 tight 2-minute day/night cycles, the drop-pod opens: extract now keeping 100% loot, OR trigger a frantic 4-minute **Overdrive Storm** for 3x Meta-Shards and boss relics (if everyone wipes, you lose the run bonus!).
6. **Core Gameplay Loop:** Pick Class in compact Hub → launch 1–4p Outpost Run (0-wait solo or party) → 60s Scavenge & Fortify (drag/weld scrap barricades + gather fuel) → 60s Wave Defense using throwable physics gadgets & class skills → repeat 4 escalating waves → Minute-8 Extract-or-Overdrive Vote → spend Meta-Shards unlocking Classes, Gadgets & Perks.
7. **First Five Minutes of Gameplay:** Spawn beside glowing Beacon Pod with instant Class select (Starter *Scout* auto-equipped) → press Deploy (10s) → Day 1 starts: chop 3 glowing scrap crates and snap 2 barricades onto Beacon perimeter (15–70s) → Night 1 hits: toss Knockback Orb into swarming critters while Beacon turret assists (70–130s) → collect Shards, upgrade Beacon shield, brace for Night 2 Stalker (2–5m).
8. **Progression System:** 8–12 distinct unlockable/upgradeable Classes (Medic, Welder, Baiter, Cryo-Thrower, Scrapper), modular Class Perk slots, Outpost Mastery milestones, and procedural Run Modifiers (`Blood Moon`, `Low-Gravity Scrap`, `Double Stalker`).
9. **Social Mechanics:** Deep role interdependence without typing via 4-icon Ping Wheel (`"Fuel Beacon!"`, `"Revive Me!"`, `"Extract!"`, `"Overdrive!"`), seamless `Player.PartyId` lobbies, shared barricade building, cooperative revives.
10. **Viral Growth Mechanisms:** High-drama *"We Voted Overdrive With 1 Barricade Left!"* Moments & YouTube challenge runs; emergent ragdoll knockback comedy; naturally drives friend-squad **Intentional Co-Play Days**.
11. **Retention Strategy:** Highest 28-day retention architecture on late-2026 Roblox—combinatorial `Classes × Run Modifiers × Squad Roles` creates infinite fresh runs with minimal new map art.
12. **Monetization Opportunities:** Proven *99 Nights / Dead Rails* fair stack: dual earn-or-buy Meta-Shards unlocking specialized Classes (100% earnable organically), Mid-Run Squad Revive Dev Product, Cosmetic Beacon/Gadget Skins, Private Servers, VIP Pass/Subscription. Zero Paid Random Items risk!
13. **Primary Competitors:** *99 Nights in the Forest*, *Dead Rails*, *Dandy's World*, *DOORS*.
14. **Competitive Differentiation:** Respects players' time with guaranteed 8–12 minute complete narrative arcs instead of 90-minute marathons, plus zero chat-wall friction for cross-age squads.
15. **MVP Features:** 1 compact procedural Outpost clearing, Beacon fuel/shield system, snap-placeable barricades, 3 enemy archetypes + 1 Overdrive Mini-Boss, 4 starter Classes, Minute-8 Extract/Overdrive vote, Ping Wheel.
16. **Estimated Development Complexity:** **Medium** (enemy pathfinding, barricade snapping, 4 class kits, run state machine; solo build ~5–8 weeks).
17. **Content Production Requirements:** **Very Low Post-Launch** — Dropping 1 new Class or 2 Run Modifiers per month multiplies combinatorial replayability across all runs.
18. **Major Risks:** Slightly heavier MVP engineering scope than `C3` or `C2`; early Night-1 difficulty spikes causing mobile newcomer quits if not carefully tuned; pathfinding lag if enemy counts aren't pooled/capped.
19. **Assumptions Requiring Validation:** That 12-minute runs feel tense and complete (not rushed), and that solo players enjoy Night 1–4 as much as 4-player squads.
20. **Proposed Prototype Experiments:** Build 1 playable 6-minute mini-run (2 waves + Overdrive vote) with 2 classes; test solo vs. 3-player squads with 25 testers measuring run completion, Overdrive vote rate (target >40%), and rematch rate.

---

## Concept C5 — *Chaos Kitchen: Throw & Serve* (Strong Organic Viral & Social Potential) — **#2 Organic Growth Priority**

1. **Working Title:** *Chaos Kitchen: Throw & Serve*
2. **One-Sentence Pitch:** An *Overcooked*-style 1–4 player chaotic physics kitchen roguelite where you hurl sizzling ingredients across moving traps to teammates, fend off absurd VIP customers, and upgrade a shared diner.
3. **Target Audience:** All-ages (`8–24`) friend squads, couples/duos, casual mobile players, and TikTok/Moments comedy clippers.
4. **Market Opportunity:** Modernizes *Work at a Pizza Place*'s immortal co-op workplace comedy (92.9% rating, 168k Sep 2026 peak, `S14`) into a fast, roguelite-escalating physics thrower—a near-empty blue ocean on 2026 Roblox (**Opportunity 5: 7.9/10**).
5. **Main Gameplay Hook:** **Full-Physics Food Throwing & Catching** — fling steaks, pizzas, and fire extinguishers across conveyor hazards straight into frying pans or teammates' hands while kitchen disasters escalate!
6. **Core Gameplay Loop:** Enter 1–4p Diner Shift (4-minute timer) → read big visual icon order bubbles (zero reading/chat required!) → chop, throw, cook, plate, and toss finished dishes onto the pass before patience bars explode → survive comedic mid-shift hazards (grease slicks, food critic, runaway rats) → earn Tips → pick 1 of 3 roguelite Shift Perks or upgrade persistent Diner decor/equipment.
7. **First Five Minutes of Gameplay:** Spawn inside bright mini-kitchen with glowing Chop Board & Fryer (0–10s) → grab burger patty, fling it across counter straight into sizzling pan (instant hilarious physics pop!), plate & serve Customer #1 (15–45s) → complete chaotic Shift 1 earning Tips and unlocking Throw-Boost Gloves (1–5m).
8. **Progression System:** Persistent Diner upgrades (faster stoves, throw-assist catch mitts, diner themes), shift star ratings, recipe/VIP customer index, endless Rush-Hour leaderboard.
9. **Social Mechanics:** Peak **Intentional Co-Play** comedy—teammates accidentally lighting pans on fire, cross-kitchen Hail Mary throws, zero text-chat reliance (pure visual food icons + funny chef emotes), native `Player.PartyId` squads.
10. **Viral Growth Mechanisms:** **Unrivaled 3-second mute clip appeal** for Roblox Moments, TikTok, and Shorts; automatic **Video Captures API** highlight trigger whenever a dish lands in a pan from >25 studs away or a kitchen fire breaks out! Prime candidate for official **Standout Games** editorial Home nomination (`S04`).
11. **Retention Strategy:** Rotating daily Kitchen Layouts & Hazard Mutators (Moving Floor, Ice Kitchen, Giant VIP Rush), cooperative star chasing with friends, persistent Diner customization.
12. **Monetization Opportunities:** Strictly family-friendly ethical cosmetics & flair: Chef Outfits/Hats/Aprons, Diner Visual Themes, Funny Throwable Emote Props, VIP Diner Club Subscription, optional Rush-Hour Retry/Tip-Doubler Rewarded Video.
13. **Primary Competitors:** *Work at a Pizza Place*, *Restaurant Tycoon 2*.
14. **Competitive Differentiation:** Fast, hilarious, physics-driven active action rather than slow tycoon waiting or static station clicking.
15. **MVP Features:** 1 compact physics kitchen, 4 stations (Chop, Cook, Plate, Extinguish), 3 simple recipes, magnetic throw-to-pan/teammate physics, 3 kitchen hazards, visual order HUD, solo/co-op dynamic order pacing.
16. **Estimated Development Complexity:** **Low–Medium** (single small room; compact prop/recipe system; solo build ~4–6 weeks).
17. **Content Production Requirements:** **Low** — New recipes and floor-hazard modifiers remix the same compact room endlessly.
18. **Major Risks:** Public-lobby griefers intentionally throwing food on the floor (mitigate via auto-respawn ingredients + vote-kick/anti-troll physics + solo/friends-only instant shift); lower ARPPU ceiling than progression RPGs/extraction games.
19. **Assumptions Requiring Validation:** That solo players enjoy 1-player Rush Shifts cleanly, and that mobile touch-throwing into pans/teammates feels joyful rather than finicky.
20. **Proposed Prototype Experiments:** Build 1 kitchen + 1 burger recipe + throw-into-pan physics in 7 days; test solo vs. 2–4p squads tracking laugh/clip moments, shift completions, and mobile throw accuracy.

---

## Concept C6 — *Relic Forge: Magnet Salvage* (Bonus Underserved Cozy-Crafting Wildcard)

1. **Working Title:** *Relic Forge: Magnet Salvage*
2. **One-Sentence Pitch:** A cozy, trust-first salvage & combinatorial forging RPG where you haul sunken relics via a crisp 5-second magnet tension-bar minigame and smelt 3-relic combos into glowing custom tools.
3. **Target Audience:** Cozy collectors, Bestiary completionists, and RPG recipe-crafters across mobile and PC (capturing *Fisch* + *The Forge* crossover demand).
4. **Market Opportunity:** Bridges *Fisch*/*Fish It!* (110k–150k+ combined daily CCU) and *The Forge* (1.05M peak, 94.45% rating, huge YouTube *"best recipe"* search traffic) without entering the red-ocean fishing niche (**Opportunities 3 & 7**).
5. **Main Gameplay Hook:** **5-Second Tactile Magnet-Lock Salvage + 3-Slot Combinatorial Forging** (fusing 3 salvaged relics passes their visual glow, trait, and power into thousands of emergent custom tools!).
6. **Core Gameplay Loop:** Cast electromagnetic grapple off atmospheric salvage pier → beat crisp 5-second active tension-bar pull (gentle mobile ergonomics) → log relic/mutation in visual Salvage Codex → either sell for Scrap OR combine 3 relics at the Anvil into a custom traited Magnet/Tool → unlock deeper salvage tides and summon shared server Tide Events.
7. **First Five Minutes of Gameplay:** Spawn steps from shimmering sunken ruins with Starter Magnet equipped → cast and land first crisp tension-bar haul (0–25s) → smelt first 3 salvaged relics into a glowing *Copper-Volt Magnet* at the pier Anvil (1–3m) → haul first Rare Storm-Charged Relic during an automated Tide Shift (3–5m).
8. **Progression System:** 60+ Salvage Codex relics × 5 tide mutations, 3-relic combinatorial trait forging table (15 base traits → 400+ emergent tool builds), salvage pier upgrades, shared Tide Totem crafting.
9. **Social Mechanics:** Cozy shared-dock hanging out, pooling currency to activate server-wide **Golden Tide** weather events, flexing glowing forged tools, YouTube/Discord *"Secret Forge Recipe"* community discovery.
10. **Viral Growth Mechanisms:** High organic YouTube/TikTok searchability (*"Top 5 Broken Relic Forge Recipes!"*), server-wide rare-salvage announcements, calm wholesome indie goodwill (*Fisch* playbook).
11. **Retention Strategy:** Deep Bestiary completion + combinatorial recipe experimentation + automated hourly Tide Modifiers + zero P2W backlash risk.
12. **Monetization Opportunities:** 100% Paid Random Items exempt: Storage/Loadout Expansion Passes, Cosmetic Magnet/Anvil Skins & Pier Decor, Shared Server Tide-Summon Totem (deterministic server-wide event, non-RNG!), VIP Club Subscription, Rewarded Video battery refills.
13. **Primary Competitors:** *Fisch*, *Fish It!*, *The Forge*, *Bee Swarm Simulator*.
14. **Competitive Differentiation:** Fresh sunken-relic salvage theme + deep combinatorial 3-slot tool crafting missing from standard fishing sims.
15. **MVP Features:** 1 stylish salvage bay with 3 depth zones, 1 super-crisp 5s tension-bar minigame, 30 starter relics + 3 mutations, 3-slot Anvil trait-combiner, Salvage Codex UI, automated hourly Tide Cycle.
16. **Estimated Development Complexity:** **Low–Medium** (proved solo-buildable by WoozyNate's *Fisch* launch; data-driven trait table keeps art scope light; ~4–6 weeks).
17. **Content Production Requirements:** **Low–Moderate** — Data-table traits & new relic meshes expand combinatorial builds far faster than hand-crafted open worlds.
18. **Major Risks:** Calmer gameplay has lower instant viral-clip velocity on Moments than chaos/heist loops; tension-bar feel must be tuned impeccably on mobile touchscreens.
19. **Assumptions Requiring Validation:** That players find the 5-second magnet pull intrinsically satisfying across 30+ repeats and actively experiment with 3-relic forging combinations.
20. **Proposed Prototype Experiments:** Build isolated magnet tension-bar + 3-slot forging anvil in 7 days; test with 20 cozy/sim players measuring casts-per-session (target ≥25) and custom forging experiments (target ≥3 unique crafts in 10 min).
