# Deliverable A — Executive Summary

**Collection Date:** `2026-11-22`  
**Primary Anchor:** Solo Indie Developer (Zero / Small Budget, USD & PHP @ `₱63.75/USD`)  
**Methodology:** Independent market discovery (44 verified experiences, 41-mechanic matrix, 12 viral case studies, late-2026 platform documentation) conducted **strictly blind** to [GameIdea.txt](../../GameIdea.txt) first, followed by unbiased product evaluation, alternative concept design, sensitivity scoring, and Python-verified financial modeling.

---

## 1. The Late-2026 Roblox Market Reality (Five Defining Findings)

1. **Massive, Maturing, De-Concentrating—Yet Ruthlessly Competitive `[Officially confirmed]` (`S01`, `S23`):** As of Q3 2026 (reported Oct 29, 2026), Roblox operates at **138M DAUs**, **~34B quarterly hours engaged**, **$1.697B quarterly bookings**, and **~$1.7B trailing 12-month DevEx payouts** (cumulative >$5B). Top-10 game share dropped from ~30% to ~20%, and **40% of the weekly Top 100 Home RFY games (by impressions) were created in the prior 3 months**—proving new games break out constantly. Yet earnings remain sharply power-law skewed (Top 1,000 creators capture ~73% of payouts; DevEx median is ~$1,440/yr), and **>80% of Top 100 titles use AI tools**, flooding the market with cheap clones.
2. **The June 15, 2026 Discovery Overhaul Killed Clickbait & AFK Simulators `[Officially confirmed]` (`S03`, `S04`):** Roblox permanently retired **QPTR** and upgraded Home *"Recommended for You"* (RFY) to a **28-day rolling window** (`D1`, `D2–7`, `D8–28`) driven by **Play-Through Rate (PTR)**, a **negative First-Play Bounce Rate (`<60s` & `61–180s`)**, **28-day Play Days Per User**, **Playtime Per User (capped at 60 min/user/game/day)**, **Intentional Co-Play Days**, and **Q3 2026 Age-Cohort Weighting** (66% of age-checked DAUs are now 13+, and **29% global / 37% U.S. are 18+**, monetizing >50% higher).
3. **Cooperation & Mechanical Mastery Separate Survivors From 99.9% Collapses `[Strongly supported by evidence]` (`Deliverable D`, `S14`):** Across our 44-game verified database, **`cooperation` appears in 93.3% of Sustained titles vs. only 40.0% of Viral spikes**. Skill-first & co-op survival games (*Illegal Soccer* >40% peak retention; *Violence District* 18%–25%; *RIVALS* 110k–200k daily CCU; *99 Nights in the Forest* 120k–204k; *Dandy's World* 113k–191k) outlast meme-raiders and shallow clones (*Plants vs Brainrots* `-99.96%`, *Garden Horizons* `-99.99%` despite a 96% like ratio!). Furthermore, **7 of the top 10 2025–2026 viral breakouts** belong to an overlapping mega-scaler network (Do Big Studios, Splitting Point/Jandel, `misfitsbsthree` owning *both* *Steal An Egg* & *Throw Food For Animals*).
4. **New 2026 Monetization Upsides & Hard Legal Traps `[Officially confirmed]` (`S06`, `S07`, `S08`, `S12`):**
   - **Upsides:** Standard DevEx rose to **`$0.0038/R$`** (Sept 2025+), **U.S. 18+ R15-compliant DevEx rose +42.1% to `$0.0054/R$`** (June 2026+), **Subscriptions pay 100% creator share Month 2+**, **Creator Rewards** pay `5 R$/Active Spender` (≥10m, first 3 games/day) + `35%` Audience Expansion, and **US–PH Tax Treaty Article 13 (W-8BEN + BIR TIN) + Wise FX** lifts Philippine net bank take-home by **+23.9% (`₱20,488` vs. `₱16,534` per 100k R$)**!
   - **Traps:** **Paid Random Items** enforcement now bans Robux-linked eggs/crates *and* **paid Luck Boosts** across BE, NL, UK (`<18`), AU (`<18`), and **Brazil (`<18`/unverified since March 17, 2026)** unless strictly gated via server-side `PolicyService` with dynamic 100% odds UI. Meanwhile, **Jan 2026 mandatory Facial Age Estimation chat segregation** forces multiplayer games to rely on **non-verbal pings/emotes**.
5. **You Don't Need 10,000 CCU to Succeed Solo (`Deliverable L`):** At just **32.5 Avg CCU (`2,500 DAU`)**, a zero-ad solo developer nets **83,600 Earned Robux/mo (`$342` / `₱21,787` gross; ~`₱18,425` net PH take-home)**, paying back a `$100` bootstrap budget in under 10 days. At **~281 Avg CCU (`15,000 DAU`)**, gross DevEx reaches **`$3,373/mo` (`₱215,028/mo`; ~`₱181,860` net PH)**—while conservative paid-ad campaigns (`$150–$800/mo`) lose money (`0.41x–0.57x` ROAS) whenever run before retention is validated.

---

## 2. Critical Verdict on `GameIdea.txt` & Top-Ranked Strategic Path

> [!WARNING]
> **Verdict on [GameIdea.txt](../../GameIdea.txt): DO NOT BUILD AS WRITTEN (`4.22 / 10`, Rank `#7 / 7` across all 5 sensitivity profiles).**  
> Borrowing static pieces of *Steal An Egg* while dropping heist adrenaline and adding **5-minute boss wait timers**, **stationary target clicking**, **undefined egg payoffs**, **unrestricted carry-exploitable portals**, and a **multi-biome solo art treadmill** directly triggers every late-2026 RFY failure mode (`<60s` bounce, 3-minute killer loop, solo burnout, and Paid Random Items legal risk).

### Top Three Validated Concepts to Prototype (Weighted Decision Matrix — Deliverable J)

| Priority | Concept | Baseline Score | Best Sensitivity Rank | Solo MVP Effort | Core Hook & Why It Wins |
| :---: | :--- | :---: | :--- | :---: | :--- |
| **#1 Primary Prototype** | **C2: Egg Heist: Boss Vault** *(Reimagined `GameIdea.txt`)* | **8.43 / 10** | **#1 Baseline, #1 Profit, #1 Organic Growth** | 4–6 weeks (~145h) | **1–4p PvE Boss-Vault Extraction:** Throw Decoy/Freeze orbs to stun patrolling giant bosses, grab glowing eggs, push deeper or sprint to exit, hatch **100% earned** Hub Guardians (capped 12h offline income). Captures *Steal An Egg* + *99 Nights* demand with zero PvP griefing, zero wait timers, zero lootbox bans! |
| **#2 Ultra-Lean Backup** | **C3: Curve Clash: Duel Pads** *(Lowest-Cost Solo Pivot)* | **8.20 / 10** | **#1 Feasibility (`8.53`)** | **2–4 weeks (~102h)** | **Physical Lobby Duel Pads (1v1/2v2/Bot):** 90-second trick-shot curve-dodgeball battles with catch-counters, public win-streak halos, zero-P2W cosmetics, zero content treadmill, and high U.S. 18+ `$0.0054` DevEx lift. |
| **#3 Retention Leader** | **C4: 12-Minute Outpost** *(Emerging Co-Op Gap)* | **8.30 / 10** | **#1 Sustainability (`8.55`)** | 5–8 weeks | **Bite-Sized Co-Op Extraction:** 12-minute scavenge-fortify-defend runs with a high-drama Minute-8 *"Extract vs. Overdrive"* vote, 4-icon non-verbal pings, and meta-class unlocks. |

---

## 3. Direct Summary of the Five Priority Research Questions (`Research.txt`)

| Research Priority | Evidence-Backed Answer |
| :--- | :--- |
| **1. Discoverability** | Clear Stage 1 Retrieval via clean niche Share Links + Roblox Moments clips + Discord/Community Flash Mob (never buy broad ads first); win Stage 2 Ranking via authentic 15s auto-play Gameplay Video, 5-slot Thumbnail Personalization (>7d untouched), `<20%` `<60s` mobile bounce, 1-CCU viability, and 28-day Play Days + Intentional Co-Play. |
| **2. Unique Gameplay Hook** | Replace generic stationary shooting/waiting with a 3-second mute-readable kinetic verb: **throwing Freeze/Decoy utility orbs to outsmart a giant Boss and sprint out of a closing Vault carrying a glowing egg (`C2`)**, or **curving trick-shot dodgeballs on physical Duel Pads (`C3`)**. |
| **3. First Five Minutes** | Action in `<15s` via glowing floor beam (zero text walls); complete first boss vault heist & hatch Guardian #1 inside **90–120 seconds**; unlock Freeze Orb by **minute 3–4**; tease Chamber 2 rare mutations by **minute 5**—beating both `<60s` and `61–180s` bounce traps. |
| **4. Development Feasibility** | Cut multi-biomes, trading, paid-RNG legal compliance, and custom chat completely from MVP. Build **1 modular transforming Vault/Arena** driven by `ConfigTables` (~102–145 solo hours) and prove fun in a **10-day greybox prototype (Gate 1)** before investing in polish. |
| **5. Retention & Profitability** | Target **D1 ≥13%–16% (GA P75–P90)**, **D7 ≥2.5%–3.9%**, **Session ≥12m** via push-your-luck replayability + co-op roles + capped 12h offline Hub. Monetize via non-RNG passes, **100%-renewal Subscriptions**, R15 U.S. 18+ **`$0.0054` DevEx**, post-2k-MAU **Rewarded Videos**, and **W-8BEN Treaty Art. 13** (15% WHT). |

---

## 4. Recommended Immediate Next Steps (Next 30 Days)
1. **Days 1–3:** Run Experiment **E1** (3 mock 16:9 thumbnails + 1-sentence concept poll on Roblox Discords/TikTok comparing `C2` vs `C3`).
2. **Days 4–13:** Build the **10-Day Greybox Prototype of `C2: Egg Heist: Boss Vault`** (1 Chamber, 1 patrolling Boss, Decoy + Freeze Orbs, heavy-egg sprint, Extraction Pad—zero art polish or shop!).
3. **Days 14–16 (Gate 1):** Watch 15–20 testers (≥50% on mobile) play silently via screenshare. **Pass (`≥70%` voluntary 2nd heist)** → proceed to Days 17–30 MVP Hub/Codex/`ProfileStore`/`AnalyticsService` build. **Fail (`<45%` after 3-day tune)** → pivot cleanly to **7-day `C3: Curve Clash` Duel-Pad prototype** with zero sunk-cost regret!
