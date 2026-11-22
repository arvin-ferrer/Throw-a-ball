# Deliverable J — Concept Decision Matrix & Sensitivity Analysis

**Collection Date:** `2026-11-22`  
**Machine-Readable Input:** [decision_matrix.json](../data/decision_matrix.json)  
**Verified Scoring Engine:** [decision_matrix.py](../scripts/decision_matrix.py) (unit-tested in [test_decision_matrix.py](../tests/test_decision_matrix.py))

---

## 1. Baseline Weighted Scoring Matrix (Section 15 Exact Weights = 100%)

**Evaluation Weights:** Demand `15%` · Retention `15%` · Feasibility `15%` · Core Appeal `10%` · Organic Discovery `10%` · Viral/Social `10%` · Differentiation `10%` · Monetization `10%` · Sustainability `5%` (**Total = `100%`**).  
**Primary Anchor:** Solo developer with zero/limited budget targeting late-2026 Roblox Home RFY (`PTR`, `First-Play Bounce Rate`, `28-day Play Days`, `Intentional Co-Play`, `Age-Cohort Weighting`).

| Rank | Concept | Dem (15%) | Ret (15%) | Feas (15%) | App (10%) | Disc (10%) | Vir (10%) | Diff (10%) | Mon (10%) | Sust (5%) | **Weighted Score** | Confidence |
| :-: | :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | ---: | :---: |
| **#1** | **C2: Egg Heist: Boss Vault** *(Reimagined PvE Extraction)* | 9.0 | 8.5 | 8.0 | 8.5 | 8.5 | 9.0 | 8.0 | 8.0 | 8.0 | **8.43 / 10** | **High** |
| **#2** | **C4: 12-Minute Outpost** *(Co-Op Extraction Roguelike)* | 9.0 | 9.0 | 7.0 | 8.5 | 8.0 | 8.5 | 8.0 | 8.0 | 9.0 | **8.30 / 10** | Med–High |
| **#3** | **C3: Curve Clash: Duel Pads** *(Ultra-Lean Solo Arcade)* | 8.0 | 8.0 | **9.5** | 8.5 | 8.0 | 8.0 | 7.5 | 7.5 | 8.5 | **8.20 / 10** | **High** |
| **#4** | **C5: Chaos Kitchen: Throw & Serve** *(Co-Op Physics)* | 7.5 | 7.5 | 8.0 | 8.5 | 8.0 | **9.5** | **9.0** | 6.5 | 7.5 | **7.98 / 10** | Medium |
| **#5** | **C6: Relic Forge: Magnet Salvage** *(Cozy + Crafting)* | 8.0 | 8.0 | 8.0 | 7.5 | 7.5 | 7.0 | 8.5 | 8.0 | 8.0 | **7.85 / 10** | Medium |
| **#6** | **C1: Orbstrike: Boss Rush** *(Improved `GameIdea.txt`)* | 7.0 | 7.0 | 6.5 | 7.5 | 7.0 | 6.5 | 7.0 | 7.5 | 6.5 | **6.95 / 10** | Med–High |
| **#7** | **C0: Preliminary Concept (`GameIdea.txt` As Written)** | 6.0 | 3.5 | 4.5 | 3.5 | 4.0 | 3.5 | 3.0 | 5.5 | 3.5 | **4.22 / 10** | **High** |

---

## 2. Evidence & Confidence Breakdown (Evidence-Supported vs. Speculative)

| Concept | Evidence-Backed Strengths `[Strongly supported by evidence]` | Speculative Assumptions Requiring Prototype Proof `[Reasonable inference]` / `[Speculative hypothesis]` |
| :--- | :--- | :--- |
| **C2: Egg Heist: Boss Vault (`8.43`)** | Verified dual market demand (*Steal An Egg* 14.3M peak + *99 Nights*/*Dandy's World* 113k–204k sustained CCU, `S14`); bounded offline income boosts D1 (`S18`); 100% exempt from March 2026 Paid Random Items bans (`S08`). | Whether PvE Boss chases sustain the same viral adrenaline as *Steal An Egg*'s PvP base-raiding without toxic player stealing. |
| **C4: 12-Minute Outpost (`8.30`)** | Co-op survival is 2026's #1 retention & session-length archetype (`S14`, `S18`); 93.3% of sustained games feature cooperation (`Deliverable D`); 12-min arc fits GameAnalytics P90 (`14.7m`) & Creator Rewards (`≥10m`). | Whether a solo developer can nail enemy pathfinding + 4-class balance within 5–8 weeks without scope creep. |
| **C3: Curve Clash: Duel Pads (`8.20`)** | *RIVALS* (110k–200k CCU) + *Illegal Soccer* (>40% peak retention!) prove instant physical Duel Pads + zero-P2W cosmetics + skill mastery build multi-year durability with near-zero content treadmill (`S14`); captures U.S. 18+ `$0.0054` DevEx (`S06`). | Whether curved dodgeball throws + catch-counters feel crisp and lag-tolerant on 80% mobile touchscreens. |
| **C5: Chaos Kitchen (`7.98`)** | *Work at a Pizza Place* (92.9% rating, 168k Sep 2026 peak) confirms workplace co-op comedy demand (`S14`); visual food icons completely bypass Jan 2026 age-gated chat walls (`S09`). | Demand ceiling & monetization ARPPU for a modern *Overcooked*-style Roblox title are unproven (no direct modern 100k+ CCU benchmark yet). |
| **C6: Relic Forge (`7.85`)** | *Fisch* (solo-built, 40k–70k CCU) + *The Forge* (1.05M peak, 94.45% rating) prove massive cozy-tension-bar + combinatorial-crafting demand (`S14`). | Whether magnet-salvage attracts the same organic thumbnail PTR as fishing/blacksmithing. |
| **C1: Orbstrike (`6.95`)** | Instant Boss Pads fix `GameIdea.txt`'s bounce trap; earned active Orb-Eggs solve the missing payoff loop. | Lower viral comedy/social clip pull than heist (`C2`), chaos (`C5`), or duel streaks (`C3`). |
| **C0: `GameIdea.txt` (`4.22`)** | High confidence in weaknesses: 5-min wait timers trigger `<60s`/`61–180s` bounce (`S03`), stationary clicking fails D7–D28 retention (`S27`), multi-biomes burn out solo devs (`S18`), Robux eggs/luck trigger regional bans (`S08`). | None — market evidence strongly disfavors shipping unchanged. |

---

## 3. Python-Verified 5-Profile Sensitivity Analysis

Re-weighting criteria across four real-world strategic priorities tests whether the top recommendations hold up under changing solo constraints (computed programmatically by [decision_matrix.py](../scripts/decision_matrix.py)):

- **Feasibility Priority:** `35%` Feasibility (solo speed-to-ship & minimal maintenance)
- **Profitability Priority:** `30%` Monetization + `15%` Demand + `15%` Retention
- **Organic Growth Priority:** `25%` Discovery + `25%` Viral/Social (zero-ad-budget virality)
- **Sustainability Priority:** `25%` Retention + `25%` Long-Term Sustainability (28-day RFY durability)

| Concept | Baseline (Section 15) | Feasibility Priority | Profitability Priority | Organic Growth Priority | Sustainability Priority |
| :--- | ---: | ---: | ---: | ---: | ---: |
| **C2: Egg Heist: Boss Vault (Reimagined PvE Extraction)** | **#1 (8.43)** | #2 (8.30) | **#1 (8.32)** | **#1 (8.58)** | #2 (8.33) |
| **C4: 12-Minute Outpost (Bite-Sized Co-Op Extraction)** | #2 (8.30) | #3 (7.97) | #2 (8.30) | #3 (8.33) | **#1 (8.55)** |
| **C3: Curve Clash: Duel Pads (Ultra-Lean Solo Arcade)** | #3 (8.20) | **#1 (8.53)** | #3 (8.00) | #4 (8.20) | #3 (8.22) |
| **C5: Chaos Kitchen: Throw & Serve (Co-Op Physics Comedy)** | #4 (7.98) | #4 (7.90) | #5 (7.58) | #2 (8.35) | #5 (7.83) |
| **C6: Relic Forge: Magnet Salvage (Cozy Skill + Crafting)** | #5 (7.85) | #5 (7.88) | #4 (7.95) | #5 (7.60) | #4 (7.95) |
| **C1: Orbstrike: Boss Rush (Improved `GameIdea.txt`)** | #6 (6.95) | #6 (6.88) | #6 (7.08) | #6 (6.85) | #6 (6.85) |
| **Preliminary Concept (`GameIdea.txt` As Written)** | **#7 (4.22)** | **#7 (4.33)** | **#7 (4.55)** | **#7 (3.95)** | **#7 (3.93)** |

### Key Sensitivity Insights
1. **`C2: Egg Heist: Boss Vault` Is the Most Robust All-Around Winner:** Ranks **#1** in Baseline (`8.43`), Profitability (`8.32`), and Organic Growth (`8.58`), and never falls below **#2** under Feasibility (`8.30`) or Sustainability (`8.33`)—while naturally honoring the user's original creative spark (throwable orbs + bosses + eggs + *Steal An Egg* energy) in a commercially sound 2026 form!
2. **`C3: Curve Clash: Duel Pads` Dominates Pure Solo Speed-to-Market:** Jumps to **#1 (`8.53`)** when **Development Feasibility** is prioritized (2–4 week MVP, zero content treadmill, Bot Duel Pad handles 1-CCU cold start, high U.S. 18+ `$0.0054` DevEx exposure).
3. **`C4: 12-Minute Outpost` Dominates Long-Term Sustainability:** Takes **#1 (`8.55`)** when maximizing 28-day retention and multi-year durability—making it the premier **second-game / expansion target** if the solo dev prefers deeper PvE survival over heist extraction.
4. **Incremental Fixes Are Not Enough:** Simply patching `GameIdea.txt` (`C1`, `#6` everywhere at `6.85–7.08`) lags far behind reimagining the loop (`C2`, `8.43`), while shipping `GameIdea.txt` unchanged (`C0`, `#7` everywhere at `3.93–4.55`) is strictly dominated across every priority.

---

## 4. Strategic Recommendation for Validation (Not Blind Production!)

> [!IMPORTANT]
> **Recommended Next Step — Validate Before Committing:** Do **NOT** jump straight into 3-month full production on *any* concept. Run fast, low-cost **10-day greybox validation prototypes** (detailed in Deliverable K) starting with **Primary Prototype #1: `C2: Egg Heist: Boss Vault`** (highest all-around score, strongest viral + profit + creative-fit synergy). Keep **Backup Prototype #2: `C3: Curve Clash: Duel Pads`** ready as an ultra-lean 7-day pivot if `C2`'s PvE heist loop fails its Gate 1/Gate 2 playtest benchmarks (or if the developer prefers a pure skill-PvP zero-content-treadmill model over PvE extraction).
