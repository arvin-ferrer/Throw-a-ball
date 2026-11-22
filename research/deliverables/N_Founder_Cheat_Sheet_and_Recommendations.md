# Deliverable N — Founder Cheat Sheet & Final Strategic Recommendation

**Collection Date:** `2026-11-22`  
**Research Scope:** Deliverable N (7 Concise Reference Lists) + Section 22 (Direct Evidence-Based Answers to All 12 Final Strategic Questions).

---

## Part 1 — Founder Cheat Sheet

### 1. Ten Most Important Market Findings (Late 2026)
1. **QPTR Is Dead — Long Live PTR + 28-Day RFY (`S03`):** On June 15, 2026, Roblox retired QPTR, introduced **Play-Through Rate (PTR)** + negative **First-Play Bounce Rate (`<60s` & `61–180s`)**, expanded RFY to **28 days**, and capped daily RFY playtime at **60 min/user/game/day**.
2. **Cooperation Separates Survivors From Flashes (`Deliverable D`):** Across 44 verified games, **`cooperation` appears in 93.3% of Sustained games vs. 40.0% of Viral spikes**—directly mirroring RFY's *Intentional Co-Play Days* signal.
3. **Top-of-Funnel Discovery Is Open (`S01`):** **40% of the weekly Top 100 Home RFY experiences (by impressions)** in Q3 2026 were created within the prior 3 months, while Top-10 concentration fell from ~30% to ~20%.
4. **7 of Top 10 Viral Hits Belong to Mega-Scaler Networks (`S14`, `S24`):** Do Big Studios, Splitting Point (Jandel), and `misfitsbsthree` (owner of *both* *Steal An Egg* & *Throw Food For Animals*) engineered most 2025–2026 multi-million CCU spikes—never compare solo expectations against studio-backed Admin Wars.
5. **High Like Ratios Do Not Prevent Extinction (`S14`):** *Garden Horizons* (**96.0% likes**, `-99.99%` collapse) and *Plants vs Brainrots* (**94.77% likes**, `-99.96%` collapse) died because upvotes measure minute-1 pleasantness, not 28-day Play Days.
6. **Roblox Is 80% Mobile & 66% Aged 13+ (`S01`, `S23`):** **29% of global / 37% of U.S. age-checked DAUs are 18+**, monetize >50% higher, and qualify for **`$0.0054/R$` DevEx (+42.1% over `$0.0038`)** in R15 experiences!
7. **Jan 2026 Age-Checked Chat Segregation Changed Multiplayer (`S09`):** Free-text chat is locked inside separate age tiers (`5–8`, `9–15`, `16–17`, `18+`); cross-age co-op requires non-verbal pings, emotes, and visual icons.
8. **Paid Random Items Law Tightened Across 5+ Major Markets (`S08`):** Robux-linked eggs/crates *and* **paid Luck Boosts** trigger mandatory `PolicyService` blocks in BE, NL, UK `<18`, AU `<18`, and **Brazil `<18`/unverified (Mar 17, 2026)**.
9. **Modest CCU Yields Real Solo Income (`Deliverable L`):** Just **32.5 Avg CCU (`2,500 DAU`)** yields `~83.6k R$/mo` (`$342` / `₱21.8k` gross); **~281 Avg CCU (`15,000 DAU`)** yields `$3,373` / `₱215k` gross (`~₱182k` net PH take-home!).
10. **W-8BEN Treaty Art. 13 + Wise Saves +23.9% Net Pesos (`S12`, `S13`, `S26`):** Claiming 15% U.S. royalty withholding with a Philippine BIR TIN and avoiding Tipalti's 1.9%–3.0% FX spread jumps net cashout per 100k Standard R$ from `₱16,534` → `₱20,488` (`₱29,115` at U.S. 18+ tier).

### 2. Ten High-Value Solo Game Design Principles
1. **Action in `<15 Seconds`:** Put a glowing floor beam straight to the core verb on spawn—zero walls of text, zero starter paywall popups.
2. **Zero Mandatory Waiting Timers:** Players trigger boss runs/matches instantly (`Vault Elevator` / `Duel Pads`); use timers strictly for optional bonus world events.
3. **1-CCU Proof Architecture:** Dynamically scale difficulty (or include an AI Bot Duel Pad) so your game feels complete even when 1 player is online.
4. **3-Second Mute Readability:** Every core action must look funny, dramatic, or impressive in a 3-second silent clip (*Roblox Moments* & Home Auto-Play Videos).
5. **Systems Multiply Content; Biomes Exhaust You:** Invest in modular `ConfigTables` (orbs, classes, traps, mutators) inside 1 transforming arena rather than hand-crafting 6 linear worlds.
6. **Non-Verbal Co-Op First:** Design a 4-icon Ping Wheel + visual role synergies so a 10-year-old and a 19-year-old coordinate cleanly across Jan 2026 chat walls.
7. **Mastery-Amplified Accessibility:** 2-button mobile thumb controls with generous auto-curve assist (`<13` friendly) + dodging/timing/push-your-luck depth (`13+/18+` sticky).
8. **Capped Asynchronous D1 Hook:** A 20-line timestamp delta granting **8–12h capped offline Hub progress** drives gentle, non-punitive D1 check-ins without AFK farming.
9. **100% Gameplay-Earned RNG Isolation:** Never sell egg currency for Robux or Paid Luck Passes—eliminate 100% of global Paid Random Items legal friction.
10. **Trust-First Ethical Monetization:** Sell extra Hub slots, cosmetics, optional mid-run revives, **100%-renewal VIP Subscriptions**, and safe-state Rewarded Videos—never nerf bought items.

### 3. Ten Fatal Mistakes to Avoid
1. **Building 3–6 months in isolation** before testing a 10-day greybox prototype on real players.
2. **Buying irreversible Ads Manager Credits (`285 R$/credit`)** before validating D1 ≥13% and Session ≥10m.
3. **Converting `$0.0054` U.S. 18+ Earned Robux into Ad Credits** (Roblox consumes `$0.0054` balances first, destroying 30.8% net value vs. paying via USD card!).
4. **Testing only on Desktop PC** and shipping `<2GB` Android RAM crashes (`Error 292`) to an 80% mobile audience.
5. **Using naive `SetAsync` DataStore saves** that overwrite player progress with blank tables on transient load errors (use `ProfileStore` + kick-on-load-fail!).
6. **Adding Peer-to-Peer Trading in an MVP** (invites race-condition duping hyperinflation + `IsPaidItemTradingAllowed` compliance traps).
7. **Relying on `AnalyticsService:LogProgressionEvent()`** (exists in Luau, produces **zero native Creator Hub charts** as of Nov 2026!).
8. **Resetting Thumbnail Personalization every 24–48 hours** or uploading CGI trailers/text overlays to Home Gameplay Videos.
9. **Using unlicensed Anime/Sanrio/Brand IP** in the Roblox License Manager era (catastrophic instant DMCA wipe).
10. **Running manual twice-weekly Admin Abuse spectacles solo** (causes weekday ghost towns, economy hyperinflation, and rapid developer burnout).

### 4. Ten Actionable Discovery Optimization Strategies (Nov 2026)
1. Upload **3–5 conceptually distinct 16:9 custom thumbnails** on `Places > Thumbnails > Home Page` and leave untouched `>7 days`.
2. Record a **12–15s authentic, unedited Gameplay Video** (`Place Settings → Videos`, hook in first 2 seconds) for up to **+39% RFY playtime lift**.
3. Instrument `LogOnboardingFunnelStepEvent` (Steps 1–5) and crush `<60s` First-Play Bounce Rate (`RFYDuration0To60`) below 20%.
4. Integrate **Video Captures API** auto-prompts on clutch escapes/KOs to fuel native **Roblox Moments** (one-tap instant Join).
5. Use **Creator Hub Share Links** on every TikTok/Shorts/Discord post (D7 attribution + **35% Audience Expansion share** at ≥100 DAU).
6. Support native **Roblox Party (`Player.PartyId`)** into reserved servers (officially credited toward **Intentional Co-Play Days** since Dec 11, 2025).
7. Build R15-compliant avatars + invoke `Player:PromptAgeCheck()` where natural to align with Q3 2026 **Age-Cohort Weighting** and `$0.0054` U.S. 18+ DevEx.
8. Queue automated **Experience Events** (`Notify Me`) + keep core game title stable (use concise bracket tags `[NEW ORB]` only).
9. Submit polished, original non-clone MVPs to Roblox's official **Standout Games** editorial nomination form (zero-cost Home slot).
10. Always judge organic algorithmic health strictly inside `Analytics > Acquisition > Home Recommendations`, never blended Overview metrics during ad tests.

### 5. Most Promising Market Opportunities (Top 4 Ranked)
1. **Short-Session Co-Op Survival / PvE Boss Extraction (`10–15 min` runs — `O1` & `O6`)**
2. **Chaotic Physics Arcade Sports & Mobile-Friendly Duel Pads (`O2` & `O8`)**
3. **Co-Op Assembly-Line Physics Comedy (*Overcooked*-style — `O5`)**
4. **Tactile Skill-Minigame Cozy Collection + Combinatorial Forging (`O3` & `O7`)**

### 6. Recommended Prototype Concepts
- **Primary Prototype #1:** **`C2: Egg Heist: Boss Vault`** (`8.43 / 10` — #1 Baseline, #1 Profitability, #1 Organic Growth).
- **Ultra-Lean Backup #2:** **`C3: Curve Clash: Duel Pads`** (`8.20 / 10` — #1 Feasibility at `8.53`, 2–4 week MVP, zero content treadmill).
- **Long-Term Alternative #3:** **`C4: 12-Minute Outpost`** (`8.30 / 10` — #1 Sustainability at `8.55`).

### 7. Immediate Practical Next Steps
1. Run 3-day Thumbnail/Concept Poll (`E1`) comparing `C2` vs. `C3`.
2. Ship 10-day greybox prototype of `C2` (1 Chamber, 1 Boss, Decoy/Freeze Orbs, Heavy Egg Extraction).
3. Observe 15–20 silent mobile/PC playtesters at Day 14 (**Gate 1**: ≥70% voluntary Run #2 → build MVP; <45% → pivot cleanly to 7-day `C3` prototype).

---

## Part 2 — Section 22: Final Strategic Recommendation (Direct Answers to All 12 Questions)

### 1. What types of Roblox games currently have the strongest evidence of commercial opportunity?
**Session-based co-op survival/extraction runs** (*99 Nights in the Forest* 120k–204k CCU, *Dandy's World* 113k–191k, *Dead Rails* 6.67B visits), **kinetic non-P2W competitive/arcade sports & duels** (*RIVALS* 110k–200k, *Illegal Soccer* >40% peak retention, *Volleyball Legends* 95.17% rating), **tactile cozy collection/combinatorial crafting RPGs** (*Fisch* 40k–70k, *Fish It!* 65k–81k, *The Forge* 94.45% rating), and **heist-extraction hybrids** (*Steal An Egg* 800k–1M+ active peaks)—particularly when adapted to **10–15 minute mobile-friendly sessions** and **R15 13+/18+ polish** (`S01`, `S14`, `S17`).

### 2. What common features appear to contribute most to successful Roblox games?
In our 44-game verified matrix (`Deliverable D`), **visibility & recognition** (`social_recognition` 100%, `visible_player_progression` 95.5%), **synchronized events** (`timed_events` 88.6%), and above all **`cooperation` (93.3% of Sustained games vs. 40.0% of Viral spikes)** plus **`achievements` (86.7% Sustained)** and **`multiple_currencies` (66.7% Sustained)** separate durable commercial businesses from fleeting spikes.

### 3. What separates temporarily viral games from sustainable games?
Temporarily viral games (*Plants vs Brainrots* `-99.96%`, *Don't Wake the Brainrots!* `-99.99%`, *Garden Horizons* `-99.99%`) rely on **ephemeral meme wrappers, shallow Rebirth/click loops, unchecked inflation, and manual Admin Abuse spikes** that leave weekday ghost towns. Sustainable games (*RIVALS*, *99 Nights*, *Illegal Soccer*, *Fisch*, *Bee Swarm*, *Violence District*) build **intrinsic skill mastery or cooperative role interdependence, systems-driven replayability (classes/mutators/PvP), bounded anti-inflation economies, and trust-first non-P2W monetization** (`S14`, `S18`).

### 4. How can a new developer improve the likelihood of organic Roblox discovery?
Respect Roblox's **June 15, 2026 Two-Stage RFY pipeline** (`S03`, `S04`): (a) seed Stage 1 Retrieval cleanly via targeted niche **Share Links**, native **Roblox Moments** clips, a coordinated **Discord + Roblox Community Flash Mob**, and an official **Standout Games** nomination; (b) win Stage 2 Ranking strictly on organic RFY cohorts by shipping an authentic 15s auto-play **Gameplay Video**, 3–5 untouched **Thumbnail Personalization** variants (`>7 days`), `<15s` onboarding eliminating `<60s` mobile bounce, 1-CCU viability, and native `Player.PartyId` + non-verbal pings driving **28-day Play Days** and **Intentional Co-Play Days**.

### 5. Which mechanics provide the greatest potential value relative to development effort?
1. **Modular `ConfigTable` Run Mutators & Automated Hourly Events** (multiplies replayability across 1 arena at ~10% of multi-biome cost).
2. **Physical Lobby Start Pads / Instant Elevators** (zero matchmaking bloat, instant `<15s` action).
3. **4-Icon Non-Verbal Co-Op Ping Wheel + Friend Haul Bonus** (unlocks *Intentional Co-Play* across Jan 2026 age-gated chat).
4. **Capped 12-Hour Offline Hub Progress** (~20 lines of Luau timestamp math driving clean D1 return).
5. **Visible 3D Status Flex** (win-streak halos, glowing Hub pedestals, Codex silhouettes — 95.5%–100% prevalence at low build cost).

### 6. What market opportunities appear underserved?
Four verified demand-backed gaps stand out (`Deliverable B`): (1) **10–15 minute bite-sized co-op survival/boss extraction runs** tailored for mobile (`O1`/`O6`), (2) **chaotic physics arcade sports & mobile-friendly curved projectile duels** (`O2`/`O8`), (3) **non-horror / comedic co-op workplace & role-extraction games** (`O4`/`O5`), and (4) **non-fishing tactile cozy salvage + combinatorial 3-item forging** (`O3`/`O7`).

### 7. Is the preliminary game idea (`GameIdea.txt`) worth pursuing, modifying, or replacing?
**Replace/Radically Reimagine — DO NOT pursue as written (`4.22 / 10`, Rank `#7 / 7`).** Five core elements—the 5-minute boss wait timer, stationary target shooting, isolated training ranges, undefined egg payoff, and unrestricted multi-biome portals—actively collide with late-2026 RFY bounce penalties, solo art limits, and Paid Random Items law. **Keep only the creative spark** (throwable orbs + giant bosses + collectible eggs) and transform it into **`C2: Egg Heist: Boss Vault`** (`8.43 / 10`), or replace it outright with ultra-lean **`C3: Curve Clash: Duel Pads`** (`8.20 / 10`).

### 8. What should the project's primary gameplay hook be?
**For Primary Concept `C2`:** *"Hurl Decoy and Freeze Orbs to outsmart patrolling giant Vault Bosses, snatch heavy glowing Eggs that slow your sprint, and vote whether to extract safely or dive one chamber deeper for Mythic mutations—without toxic PvP stealing."*  
It is readable in **3 seconds on mute**, works cleanly at **1 CCU or 4-player co-op**, and gives hatched eggs an unmistakable visual + bounded-offline Hub payoff.

### 9. Which game concept should be prototyped first, and why?
Prototype **`C2: Egg Heist: Boss Vault`** first (**10-day greybox sprint**), keeping **`C3: Curve Clash: Duel Pads`** as the immediate backup pivot. `C2` achieves the highest overall score (**`8.43 / 10`**), ranks **#1** in Baseline, Profitability (`8.32`), and Organic Growth (`8.58`), never drops below **#2** in Feasibility (`8.30`) or Sustainability (`8.33`), directly leverages 2026's two hottest verified demand curves (*Steal An Egg* + *99 Nights* co-op extraction), and aligns naturally with the developer's creative interest in throwable balls, bosses, and eggs.

### 10. How can its commercial potential be tested with minimal financial investment?
Total pre-commitment validation cost: **`$50 – $100` (`₱3,188 – ₱6,375`)** across 3 staged gates:
1. **`$0` Concept & Clip Test (Days 1–3):** Post 3 mock 16:9 thumbnails + 15s prototype clips to Roblox Discords/TikTok (`E1`).
2. **`$0` 10-Day Greybox Screenshare Alpha (Days 4–16):** Observe 15–25 testers (≥50% mobile) silently; enforce **Gate 1** (`≥70%` voluntary 2nd heist).
3. **`$50–$100` Controlled Soft-Launch Diagnostic (Week 4–5):** Seed 400–600 real users via Share Links + a `$15–$25/day` 3–4 day Ads Manager diagnostic (untouched 48h learning phase) alongside 3–5 Thumbnail Personalization variants (`>7 days`) to measure real `<60s` bounce, Avg Session, D1/D7, and early non-RNG shop CVR (`E3`–`E11`).

### 11. What evidence would justify committing to full development & scaling?
Commit to Month 2–3 live-ops expansion and paid UA reinvestment **ONLY** when soft-launch organic/diagnostic telemetry (`n ≥ 500` unique D0 players) clears **Gate 4**:
- **`<60s` First-Play Bounce Rate:** Controlled (`<20%–25%`), zero critical `<2GB` Android OOM crashes (`<5%` crash threshold).
- **Average Session Length:** **≥11–12+ minutes** (beating GameAnalytics P50 `9.8m` and Creator Rewards `10m` threshold).
- **Day 1 Retention:** **≥13%–16%+** (GameAnalytics P75–P90, beating Creator Hub `Similar Experiences` P50).
- **Day 7 Retention:** **≥2.5%–3.9%+** (GameAnalytics P75–P90) with rising organic `Home Recommendations` impressions.
- **Monetization & Sentiment:** Ethical non-RNG **CVR ≥2.0%–3.0%+** with public **Like Ratio ≥85%+**.

### 12. What should the developer accomplish within the next 30 days?

| Week | Concrete Solo Execution Milestones | Hard Output / Gate |
| :--- | :--- | :--- |
| **Days 1–3** | Lock R15 project scaffold; create 3 mock 16:9 thumbnails (`C2` vs. `C3`); run Experiment `E1` community poll; register Philippine **BIR TIN / W-8BEN** paperwork checklist for future 15% DevEx treaty rate. | Validated concept direction + clean project repo. |
| **Days 4–10** | Build **10-Day Greybox Prototype of `C2`** (1 modular Chamber, 1 patrolling/telegraphed Boss AI, Decoy & Freeze utility orbs with mobile thumb curve-assist, heavy-egg carry slowdown, Extraction Pad, 1–4p HP scaling). | Playable greybox vertical slice (0% wasted art polish). |
| **Days 11–16** | Instrument `AnalyticsService:LogOnboardingFunnelStepEvent` (Steps 1–5); run **Closed Alpha (`n = 20` silent screenshares, ≥50% real mobile phones)**; pass **Gate 1 (`≥70%` Run #2 rate)** *(or execute immediate 7-day pivot to `C3`!)*. | **Gate 1 Go/Pivot Verdict** + fixed top 3 UX/mobile bugs. |
| **Days 17–24** | Build **MVP Core**: Personal Vault Hub (8 pedestals + **capped 12h offline income** via `ProfileStore` session-locking), Chambers 2–3 + Boss #2 + 4 Chamber Mutators, 20 **100% earned-only** Vault Guardians + Codex, 4-icon non-verbal Ping Wheel, `Player.PartyId` elevator. | Feature-complete Public MVP build. |
| **Days 25–30** | Wire dynamic `GetProductInfo()` ethical shop (4 non-RNG passes/products + Regional Pricing + Private Servers), server-side `PolicyService` fail-closed check (verify BE/NL/UK/AU/BR in Studio Player Emulator), Content Maturity Questionnaire, `<2GB` Android RAM audit, **3–5 custom 16:9 thumbnails + 15s raw Gameplay Video**, Discord + Roblox Community + Share Links → **Launch Public Beta / Soft Launch!** | Live Soft-Launch telemetry collecting Gate 3 & Gate 4 data! |
