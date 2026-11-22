# Deliverable M — Launch, Packaging & User Acquisition Strategy

**Collection Date:** `2026-11-22`  
**Research Scope:** Section 11 of `Research.txt` — End-to-End 6-Stage Release Pipeline, Late-2026 Packaging & Thumbnail Personalization Science, 3 Budget-Tier Launch Playbooks, and Quantitative Go/Fix/Kill Ad-Spend Governance (`S03`–`S05`, `S07`, `S10`, `S17`, `S27`).

---

## 1. End-to-End Six-Stage Launch & Live-Ops Pipeline

| Stage | Access Mode & Objective | Mandatory Execution & Quality Gates (`S04`, `S08`, `S11`) |
| :--- | :--- | :--- |
| **1. Pre-Launch (QA & Seeding)** | Private / Early Tester access. Start posting raw 15s physics/mechanic devlog clips on TikTok/Shorts 2–3 weeks early. | Multi-client test (`StudioTestService`, 4–8 clients); lag audit (`Network Simulator`); mobile/console check (`StudioDeviceSimulatorService` + real 2–3GB Android); `ProfileStore` session-locking + `ProcessReceipt` test; `PolicyService` Player Emulator check (BE/NL/UK/AU/BR); `AnalyticsService` Steps 1–5; Content Maturity Questionnaire; 3–5 custom 16:9 thumbnails + `512×512` icon + 15s raw Gameplay Video. |
| **2. Closed Alpha** | Whitelisted 15–30 testers via Discord / Roblox Community. | Watch **10 silent live screenshares** (zero hints!) to expose every spawn/mobile hesitation in the first 60s; validate Gate 1 Hook Proof (`≥70%` voluntary 2nd run). |
| **3. Public Beta** | Open Beta (or optional 25–50 R$ Paid Access for serious feedback) clearly labeled in description. | Stress-test server memory (`<50%` of `6.4GB + 100MB×MaxPlayers`) and DataStore budgets; fix top 3 `Funnels` Step 1→3 drop-offs & top client errors before spending a single dollar on UA. |
| **4. Soft Launch (Diagnostic)** | Public + small isolated diagnostic cohort (Share Links + optional `$50–$100` Ads test over 3–5d). | Enable 5-slot **Thumbnail Personalization** (untouched `>7 days`!); let Ads Manager complete its **24–48h Learning Phase** untouched; audit `Acquisition > Home Recommendations` strictly separately from paid traffic; evaluate against Gate 4 (D1 ≥13%, Session ≥11m). |
| **5. Full Launch ("Flash Mob")** | Synchronized public push concentrating initial concurrency into a tight 15-minute window. | Trigger Discord `@everyone`, Roblox Community shout, scheduled **Experience Event** (`Notify Me`), creator/TikTok Share Links, and **Roblox Moments** Video Captures API; stand by for 2-hour launch hotfixes; submit polished build to **Standout Games** curation form. |
| **6. Sustainable Live-Ops** | Predictable bi-weekly systemic updates (1 new Orb/Mutator/Cosmetic) + automated hourly events. | Keep up to 10 upcoming **Experience Events** queued; send **Experience Notifications** sparingly (`≤1/user/day`, major updates only to avoid spam throttling); run A/B tests via Creator Hub **Configs & Experiments**; monitor `Economy` Average Wallet Balance weekly. |

---

## 2. Packaging, Branding & Thumbnail Testing Science (Nov 2026)

### 2.1 High-Conversion Asset Standards `[Officially confirmed]` `[Developer-reported experience]` (`S04`, `S27`)
- **Game Name Stability:** Keep the core brand title short, punchy, and **permanent** (e.g., *Egg Heist: Boss Vault* or *Curve Clash*)—Roblox Search explicitly warns that changing core titles destroys search indexing and returning-player recall. Use brief bracket tags (`[NEW ORB]`, `[STORM EVENT]`) solely to signal live freshness.
- **Square Icon (`512×512` min):** Must read clearly when shrunk to `128×128` mobile grids—use **one giant expressive focal object/character + stark contrasting background**; zero tiny text! *(Roblox lacks native automated Icon A/B testing, so inspect icon pop visually against live Home/Search neighbors using preview mockups before publishing.)*
- **Mandatory Custom 16:9 Thumbnails (`1920×1080`):** Hard eligibility gate for Home RFY (`S04`). Upload **3–5 conceptually distinct variants** under `Places > Thumbnails > Home Page` (decoupled from the 10-slot Experience Details Page gallery!):
  - *Variant A (Core Tension):* Hero mid-sprint holding glowing Mythic Egg while giant Boss lunges behind.
  - *Variant B (Mechanic Hook):* Close-up glowing Freeze Orb mid-throw freezing Boss mid-swing.
  - *Variant C (Social Co-Op):* 3 friends celebrating/hauling giant mutated eggs on Extraction Pad.
  - *Variant D (Reward Aspiration):* Bright personal Vault Hub glowing with towering Golden Guardians.
- **Thumbnail Personalization Discipline:** Thanks to Roblox's Mid-2025 **Winning Thumbnail Memory**, adding a fresh variant no longer wipes winners—**NEVER reset or wipe tests daily**; let every test stabilize **≥7 full days** so cohort routing (especially across age brackets) converges (`S04`).
- **Auto-Playing Gameplay Videos (`Place Settings → Videos`):** Tested by Roblox at up to **+39% RFY playtime lift** (`S04`). Record **12–15 seconds of crisp, real, unedited core gameplay** showing the visual hook in the first **2 seconds** (NO cinematic trailers, NO voiceovers, NO lyric music, NO promotional text overlays—all violate guidelines!). Keep crisp static 16:9 fallbacks for Console/VR.
- **Front-Loaded Descriptions:** Put the clearest 1–2 sentence core-loop summary and natural genre terms at the very top (powers Semantic Search indexing without keyword stuffing).

### 2.2 Interpreting Conversion vs. Bounce Diagnostics (Anti-Clickbait Rule)
Always read **CTR / PTR** and **First-Play Bounce Rate (`<60s` / `61–180s`)** strictly as a pair:
- **High CTR/PTR + Low `<60s` Bounce:** Genuine product-packaging fit → scale!
- **High CTR/PTR + High `<60s` Bounce (`>35%–40%`):** **Expectation mismatch (unintentional clickbait) OR mobile join lag** → your thumbnail overpromises action that takes too long to reach on spawn, or mobile clients are crashing.
- **Low CTR (`<1%`) + Strong D1 (`≥13%`) & Session (`≥12m`):** Hidden gem trapped behind weak packaging → stop feature dev for 48 hours and overhaul thumbnails/icon/Gameplay Video!

---

## 3. Three Budget-Tier User Acquisition Playbooks

### Tier 1: Zero-Budget Solo Developer (`$0` / `₱0` Ad Spend) — *Primary Bootstrap Playbook*
1. **Native Roblox Moments First (Zero Redirect Loss):** Integrate Roblox's **Video Captures API** to suggest saving 30s clips on clutch 1-HP boss escapes or insane curve KOs, and post 1–2 punchy daily highlight clips natively to **Roblox Moments** (one-tap instant Join directly into the game, `S05`).
2. **Short-Form Devlogs & Chaos Clips (TikTok / YouTube Shorts / Reels):** Film 15–25s vertical videos with **2-second visual hooks** (*"I added a Freeze Orb that traps a 40-foot Boss mid-air..."*, *"Watch what happens when my friend steals the boss's Golden Egg!"*). Always attach a tracked **Creator Hub Share Link** (giving D7 retention attribution per video AND unlocking **35% Audience Expansion Rewards** once ≥100 avg DAU, `S07`).
3. **Dual-Age Community Hub (Avoid the `<13` Discord Blindspot!):** Build a **Discord server** for `13+` playtesters, bug reports, and launch coordination **AND** an official **Roblox Community (Group)** + **Experience Events (`Notify Me`)** to capture Roblox's **34% under-13 DAU** who cannot legally use Discord (`S01`, `S09`).
4. **Coordinated "Flash Mob" Launch Drop:** Never open publicly to 0 players. Rally 50–150 Discord/Community testers into a single Friday/Saturday launch window (first 15 minutes) to create instant populated servers and cleanly clear Home RFY **Stage 1 Retrieval**.
5. **Official *Standout Games* Editorial Nomination:** Submit your polished, original non-clone build via Roblox's official monthly-reviewed **Standout Games** nomination form for zero-cost Home editorial placement (`S04`).

### Tier 2: Limited-Budget Solo / Duo (`$50 – $300` | `₱3,188 – ₱19,125`)
1. **Split Budget into Two Gates (Never Dump All on Day 1!):**
   - **Sprint 1 (`$50–$100` Diagnostic Test):** Run **`$15–$25/day` for 3–4 days** via **Roblox Ads Manager** (`Plays` / `Acquire New Users` objective, funded via **USD card** if earning `$0.0054` U.S. 18+ Robux!). Leave completely untouched through the **24–48h Learning Phase**.
   - **Pause & Diagnose (Days 5–10):** Audit `Analytics > Acquisition > Home Recommendations` (ignoring blended Overview noise!) and `Funnels`. Fix the top 2 FTUE bounce cliffs and drop losing thumbnail variants.
   - **Sprint 2 (`$100–$200` Validated Weekend Surge):** Concentrate remaining spend into a **Friday–Sunday launch/update window** synced with a scheduled **Experience Event** + optional `$50–$100` micro-creator/clipping test (`$0.90–$1.50` CPM with `$150` video cap) once D1 ≥13% and Session ≥10m are verified!

### Tier 3: Reinvesting Small Team (`$1,000+` / Revenue-Funded Growth Loop)
1. **Ads Manager Earnings Objective (ROAS Scaling):** Transition from raw Plays to **Earnings Objective**, monitoring **ROAS & Estimated ROAS** alongside Roblox's verified incrementality lift (`+14%` sessions / `+10%` D7, `S10`).
2. **Disciplined 20%–30% Step Scaling:** Reinvest **4%–10% of net monthly DevEx** (higher only when attributed ROAS ≥100% or verified organic RFY halo makes blended LTV > CPP). Never jump daily budgets `10x` overnight (breaks auto-bidding CPMs)—step budgets up `20%–30%` max synced to bi-weekly weekend updates.
3. **Multi-Channel Creator Flywheel:** Pair **Performance Clipping Campaigns** (`$0.90–$1.50` CPM on TikTok/Shorts/Reels with FTC `#ad` disclosures) with **Roblox Creator Affiliate Share Links** (paying external YouTubers up to 50% platform share on new-user spend for 6 months, `S07`) and structured YouTube challenge outreach (*"Can You Beat Depth-5 Solo?"*).

---

## 4. Quantitative Ad-Spend Go / Fix / Kill / Scale Governance Matrix

Evaluate strictly **after** completing a 3–5 day diagnostic run (past the 24–48h Learning Phase), anchored to GameAnalytics' 2026 Roblox benchmarks (`S17`) and Creator Hub `Similar Experiences` percentile bands (`S11`):

| Decision State | Quantitative Trigger Thresholds | Root Diagnosis | Mandatory Action |
| :--- | :--- | :--- | :--- |
| **KILL / STOP ADS** | `D1 < 8.4%` (below GA P25) **OR** `Avg Session < 6.0m` **OR** severe `<60s` Bounce **OR** `CPP >> Estimated 30d LTV` with zero organic RFY lift | Core loop, FTUE, or mobile stability is broken; paid ads are pure cash burn. | **Pause all Ads Manager spend immediately.** Fix onboarding/mobile OOM or pivot concept before spending another dollar. |
| **FIX PACKAGING ONLY** | Ads `CTR < 0.8%–1.0%` or high CPP (`>$0.60`), **BUT** entrants deliver `D1 ≥ 13%–16%` & `Session ≥ 10–12m` | Strong game trapped behind weak icon, unclear title, or cluttered thumbnails. | **Hold ad scale.** Commission/redesign 3–5 crisp 16:9 thumbnails + authentic 15s Gameplay Video; test untouched ≥7 days. |
| **FIX FUNNEL / SHOP (HOLD)** | Healthy `CTR ≥ 1.2%+` & `D1 ≥ 10.3%–12.9%`, **BUT** `D7 < 1.6%–2.5%` **OR** `ROAS < 60%` (`CVR < 1.5%`) | Good initial hook, but weak mid-term loop or under-optimized shop value. | **Cap spend to small test only.** Add mutators/co-op goals (for D7) or enable Regional Pricing + post-minute-5 Starter Pack + VIP Sub (for CVR). |
| **GO (CONTROLLED TEST)** | `CTR ≥ 1.2%–2.0%+`, low `<60s` bounce, `D1 ≥ 13%–16%` (P75–P90), `D7 ≥ 2.5%–3.9%`, `Session ≥ 12m`, organic RFY rising | Validated retention engine ready for monetization & ROAS optimization. | Run 7–14 day controlled tests (`$15–$50/day`), activate Earnings Objective + Roblox Moments + creator Share Links. |
| **SCALE (REINVEST)** | `D1 ≥ 16%–22%+` (P90–P99), `D7 ≥ 3.9%+`, `D30 ≥ 2.0%+`, `Session ≥ 15m+`, rising Co-Play, **Attributed ROAS ≥ 100%** (or ≥75% w/ verified organic RFY halo) | Proven profitable growth flywheel compounding 28-day organic Home RFY. | Reinvest **4%–10%+ of net earnings**, stepping daily budgets `+20%–30%` max on weekend update drops + CPM clipping. |
