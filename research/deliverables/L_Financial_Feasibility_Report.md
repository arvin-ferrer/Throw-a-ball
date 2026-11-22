# Deliverable L — Financial Feasibility Report (USD & PHP Modeling)

**Collection Date:** `2026-11-22`  
**Machine-Readable Parameters:** [financial_assumptions.json](../data/financial_assumptions.json)  
**Verified Calculation Engine:** [financial_model.py](../scripts/financial_model.py) (unit-tested in [test_financial_model.py](../tests/test_financial_model.py))

> [!IMPORTANT]
> **Methodological Integrity Rules Enforced:**
> 1. **Zero CCU-to-Revenue Guesswork:** Revenue is **never** fabricated directly from concurrent player counts. Instead, monthly gross Robux derives strictly from `MAU × Monthly Payer Conversion × Monthly ARPPU`, while **Implied Avg CCU** derives cleanly from `DAU × Sessions/Day × Avg Session Minutes ÷ 1,440`.
> 2. **Strict Separation of Gross Spend vs. Withdrawable Cash:** Player-spent Robux undergoes Roblox's **30% Marketplace cut**, converts at verified late-2026 **DevEx rates** (`$0.0038` standard / `$0.0054` U.S. 18+ tier), and—for Philippine developers—faces **U.S. Royalty Withholding Tax (15% with treaty vs. 30% without)** plus **FX transfer spreads**.

---

## 1. Verified Late-2026 Platform Rates, FX & Mathematical Formulas

### 1.1 Dated Platform & Exchange Rate Inputs (`2026-11-22`) `[Officially confirmed]` `[Strongly supported by evidence]`

| Parameter | Verified Value (`2026-11-22`) | Source & Legal Context |
| :--- | :--- | :--- |
| **Marketplace / Experience Platform Cut** | **30%** (Creator keeps **70%**) | Game Passes, Dev Products, Paid Private Servers; Subscriptions keep **100% Month 2+** (`S07`). |
| **Standard DevEx Rate** | **`$0.0038` per Earned Robux** (`$114` / 30k R$ min) | Effective **Sept 5, 2025** (+8.5% over legacy `$0.0035`); 1 cashout/month via Tipalti (`S06`). |
| **U.S. 18+ Qualifying DevEx Rate** | **`$0.0054` per Earned Robux** (`$162` / 30k R$ min) | Effective **June 8, 2026** (+42.1% vs standard) for age-verified U.S. 18+ spend in **R15-compliant** experiences (`S06`). |
| **Creator Rewards (Daily Engagement)** | **5 Robux** / Active Spender (`≥$9.99`/60d) playing ≥10m in first 3 games/day | Launched July 24, 2025; modeled conservatively at `3–12 R$/DAU/month` (`S07`). |
| **USD → PHP Exchange Rate (`2026-11-22`)** | **`₱63.75 / $1.00 USD`** *(modeling midpoint)* | **BSP Reference Rate (Nov 20, 2026):** `₱63.6960`; **BAP/PDS close:** `₱63.81`; **Wise/XE mid-market:** `₱63.65–₱63.85` (`S13`, `S26`). |
| **Roblox Ads Manager Ad Credit Parity** | **`1 Ad Credit = $1.00 USD = 285 Robux`** | Min 10 credits (`2,850 R$`), **irreversible**; U.S. 18+ `$0.0054` Robux consumed first (`S10`). |

### 1.2 Explicit Modeling Formulas (`financial_model.py`)
- $\text{Implied Avg CCU} = \frac{\text{DAU} \times \text{Sessions/Day} \times \text{Avg Session Minutes}}{1{,}440}$
- $\text{MAU} = \text{DAU} \times \text{MAU-to-DAU Ratio}$ *(reflecting ~26%–32% monthly stickiness)*
- $\text{Monthly Gross Player Robux} = \text{MAU} \times \text{Monthly Payer Conversion} \times \text{Monthly ARPPU (R\$)}$
- $\text{Monthly Earned Developer Robux} = (\text{Gross Robux} \times 0.70) + (\text{DAU} \times \text{Monthly Creator Rewards R\$/DAU})$
- $\text{Effective DevEx Rate} = (\$0.0038 \times (1 - s_{18+})) + (\$0.0054 \times s_{18+})$ *(where $s_{18+}$ is qualifying U.S. 18+ spend share)*
- $\text{Gross Developer Earnings (USD)} = \text{Monthly Earned Robux} \times \text{Effective DevEx Rate}$
- $\text{Monthly Operating Profit (USD)} = \text{Gross Developer Earnings (USD)} - (\text{Monthly Ad Spend} + \text{Monthly Maintenance})$
- $\text{Break-Even DAU} = \lceil \text{Monthly Operating Cost} \div (\text{Dev Earnings USD} \div \text{DAU}) \rceil$
- $\text{Ad ROAS} = \text{Dev Earnings USD} \div \text{Monthly Ad Spend USD}$
- $\text{Upfront Cost Recovery (Months)} = \text{Upfront Dev Cost USD} \div \text{Monthly Operating Profit USD}$

---

## 2. Python-Computed 9-Scenario Financial Feasibility Matrix (USD & PHP)

All figures below were computed programmatically by [financial_model.py](../scripts/financial_model.py) using [financial_assumptions.json](../data/financial_assumptions.json) (`FX = ₱63.75/USD`, dated `2026-11-22`). **Dev Earnings** represent gross withdrawable DevEx before U.S. royalty tax withholding (detailed in Section 3 below).

| Resource Profile | Scenario | DAU | Implied Avg CCU | Gross Robux/mo | Earned Robux/mo | Gross DevEx (USD/mo) | Gross DevEx (PHP/mo) | Operating Profit (USD/mo) | Operating Profit (PHP/mo) | Break-Even DAU | Ad ROAS | Payback (mo) |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Solo Bootstrap** *(Anchor: $100 upfront, $0 ads, $10–$25 maint)* | **Conservative** | 300 | 2.7 | 4,514 | 4,060 | $16.08 | ₱1,024.97 | **$6.08** | **₱387.47** | 187 | Organic | 16.5 |
| **Solo Bootstrap** *(Primary Anchor)* | **Moderate** | 2,500 | 32.5 | 98,000 | 83,600 | **$341.76** | **₱21,787.00** | **$331.76** | **₱21,149.50** | 74 | Organic | **0.3** |
| **Solo Bootstrap** *(Primary Anchor)* | **Optimistic** | 15,000 | 281.2 | 967,680 | 812,376 | **$3,372.99** | **₱215,027.80** | **$3,347.99** | **₱213,434.05** | 112 | Organic | **<0.1** |
| **Polished Solo / Duo** *($600 upfront, $150/mo ads, $40–$100 maint)* | **Conservative** | 800 | 8.6 | 17,389 | 15,372 | $62.10 | ₱3,959.10 | **-$127.90** | **-₱8,153.40** | 2,448 | **0.41x** | N/A *(Loss)* |
| **Polished Solo / Duo** *(Limited Budget)* | **Moderate** | 6,000 | 86.7 | 279,300 | 237,510 | **$978.54** | **₱62,382.00** | **$788.54** | **₱50,269.50** | 1,165 | 6.52x | **0.8** |
| **Polished Solo / Duo** *(Limited Budget)* | **Optimistic** | 35,000 | 738.9 | 2,620,800 | 2,184,560 | **$9,175.15** | **₱584,915.94** | **$8,925.15** | **₱568,978.44** | 954 | 61.17x | **0.1** |
| **Reinvesting Team** *(2–3 Devs: $2.5k upfront, $800/mo ads, $400–$600 maint)* | **Conservative** | 4,000 | 50.0 | 129,024 | 112,317 | $459.15 | ₱29,270.88 | **-$740.85** | **-₱47,229.12** | 10,455 | **0.57x** | N/A *(Loss)* |
| **Reinvesting Team** *(2–3 Devs)* | **Moderate** | 25,000 | 428.0 | 1,530,000 | 1,283,500 | **$5,370.16** | **₱342,347.96** | **$4,170.16** | **₱265,847.96** | 5,587 | 6.71x | **0.6** |
| **Reinvesting Team** *(2–3 Devs)* | **Optimistic** | 100,000 | 2,361.1 | 9,300,000 | 7,710,000 | **$32,752.08** | **₱2,087,945.10** | **$31,352.08** | **₱1,998,695.10** | 4,275 | 40.94x | **0.1** |

### Key Modeling Takeaways for a Solo Developer
1. **You Do NOT Need 10,000 CCU to Build a Meaningful Income:** At just **32.5 Avg CCU (`2,500 DAU`)**, a zero-ad solo developer clears **83,600 Earned Robux/month (`$342` / `₱21,787` gross)**—exceeding Roblox's 30,000 R$ DevEx threshold every single month and recovering `$100` in upfront costs in under 10 days. At **~281 Avg CCU (`15,000 DAU`)**, gross DevEx reaches **`$3,373/month` (`₱215,028/month`)**!
2. **The 30,000 R$ DevEx Cashout Threshold Reality:** In the **Solo Conservative** tier (`300 DAU` / `2.7 Avg CCU`), `4,060 Earned Robux/month` means waiting **~7.4 months** to reach the 30,000 R$ minimum cashout (`$114` gross). Solo devs must plan for zero cash withdrawals during Months 1–3 of early growth.
3. **Paid-Ad Burn Exposure Is Brutal at Small Scale:** Notice that BOTH paid-budget **Conservative** scenarios (`$150/mo` ads at 800 DAU → **`-₱8,153/mo`** loss, `0.41x` ROAS; `$800/mo` ads at 4,000 DAU → **`-₱47,229/mo`** loss, `0.57x` ROAS) bleed cash immediately—mathematically confirming why Gate 4 prohibits scaling paid ads until organic retention & conversion are proven!
4. **Rewarded Video & Subscription Upside (Not Counted Above):** Adding Month 2+ **0%-fee Subscriptions** (`S07`) and post-2,000-MAU **Rewarded Video Ads** (reported 15%–40% incremental lift across non-payers, `S26`) provides meaningful pure-margin upside above these conservative projections.

---

## 3. Philippine Solo Developer Net Take-Home & Tax/FX Optimization (`2026-11-22`)

Because Roblox classifies DevEx payouts as **royalties** (issuing **Form 1042-S** to non-U.S. creators via Tipalti), two administrative decisions alone swing a Philippine solo developer's real bank take-home by **+23.9% more pesos per Robux** `[Officially confirmed]` `[Strongly supported by evidence]` (`S06`, `S12`, `S13`, `S26`):

| Cashout Configuration (Per 100,000 Earned Robux) | Gross USD | U.S. Royalty WHT | FX Channel (`₱63.75` Mid) | **Net Bank Take-Home (USD / PHP)** | Net PHP / 1 R$ |
| :--- | :---: | :---: | :--- | :---: | :---: |
| **Unoptimized Default** *(Standard `$0.0038`, No Treaty, Tipalti PHP FX -2.5%)* | `$380.00` | **30%** (Default) | Tipalti (`₱62.16`) | `$266.00` / **`₱16,534`** | `₱0.1653` |
| **Optimized PH Solo** *(Standard `$0.0038`, W-8BEN + BIR TIN Treaty Art. 13, Wise USD→PHP -0.5%)* | `$380.00` | **15%** (US–PH Art. 13) | Wise (`₱63.43`) | `$323.00` / **`₱20,488`** | **`₱0.2049`** |
| **Optimized PH Solo — U.S. 18+ Tier** *(`$0.0054`, W-8BEN Treaty Art. 13, Wise USD→PHP -0.5%)* | `$540.00` | **15%** (US–PH Art. 13) | Wise (`₱63.43`) | `$459.00` / **`₱29,115`** | **`₱0.2912`** |

*(Excludes minor fixed wire/ACH fees `~$1–$5` and local Philippine BIR income tax filing obligations; consult a PH CPA regarding foreign tax credits on Form 1042-S.)*

**Applied to Solo Bootstrap Anchor (Net PH Bank Take-Home after 15% Treaty WHT + Wise FX):**
- **Moderate (`2,500 DAU`, 83.6k R$):** Gross `₱21,787` → **Net Take-Home ~`₱18,425 / month`** (`~$290.50` net).
- **Optimistic (`15,000 DAU`, 812.4k R$):** Gross `₱215,028` → **Net Take-Home ~`₱181,860 / month`** (`~$2,867` net).

> [!CAUTION]
> **Critical Ad Credit Arbitrage Trap (`S06`, `S10`):** Converting Robux into Ad Credits (`1 Ad Credit = $1.00 = 285 R$`) **consumes `$0.0054` U.S. 18+ Earned Robux FIRST**! Converting 285 R$ of `$0.0054` Robux burns **`$1.539` gross (`$1.308` post-15% tax) to buy `$1.00` of ads—destroying 30.8% net value**. If your game earns U.S. 18+ Robux, **always fund Roblox Ads Manager via USD credit/debit card**, never via Robux Ad Credit conversion! *(Conversely, converting pure `$0.0038` Standard Robux values 285 R$ at `$0.9206` post-15% PH tax, slightly beating cashing out and re-depositing.)*

---

## 4. Itemized Solo Indie Launch Budgets (USD & PHP @ `₱63.75`)

Roblox Studio, Blender, Audacity, and game server hosting cost **`$0`** `[Officially confirmed]`. Realistic freelance commission ranges (DevForum, Talent Hub, HiddenDevs, `S28`) produce three launch tiers:

| Budget Tier | Total USD | Total PHP (`@ ₱63.75`) | Recommended Itemized Allocation |
| :--- | :--- | :--- | :--- |
| **1. Ultra-Lean Bootstrap** *(Recommended Anchor!)* | **`$50 – $200`** | **`₱3,188 – ₱12,750`** | DIY Studio/Blender/UI (`$0`) + 1–2 pro Icon/16:9 Thumbnails (`$20–$60`) + free/minimal SFX (`$0–$15`) + focused `$30–$125` weekend Ads diagnostic test + organic TikTok/Moments devlogs. |
| **2. Polished Solo / Duo** | **`$300 – $900`** | **`₱19,125 – ₱57,375`** | Complete 5-slot GFX A/B pack (`$60–$120`) + polished UI templates (`$50–$150`) + custom SFX/BGM (`$50–$130`) + key hero 3D models (`$50–$150`) + `$100–$350` structured launch test. |
| **3. Commercial Indie Studio** | **`$1,200 – $3,000+`** | **`₱76,500 – ₱191,250+`** | Pro GFX + trailer (`$150–$350`) + scripted UI (`$150–$300`) + custom world/UGC assets (`$300–$800`) + audio (`$100–$250`) + `$500–$1,300+` Ads Manager + micro-creator CPM clipping. |
