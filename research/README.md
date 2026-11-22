# Roblox Deep Market Research & Product Validation Vault

**Collection Date:** `2026-11-22`  
**Primary Anchor Profile:** Solo Indie Developer (Zero / Small Budget, USD & PHP @ `₱63.75/USD`) + Multi-Scenario Comparisons  
**Visual Results Summary (Charts + Diagrams):** [Research_Results_Visual_Summary.md](../Research_Results_Visual_Summary.md)  
**Compiled Single-File Report:** [Roblox_Deep_Research_Report.md](../Roblox_Deep_Research_Report.md)

---

## Navigation Index (Deliverables A–N + Section 22)

| Deliverable | Document | `Research.txt` Scope |
| :--- | :--- | :--- |
| **A** | [A_Executive_Summary.md](deliverables/A_Executive_Summary.md) | Executive synthesis, 5 priority answers & 30-day direction |
| **B** | [B_Roblox_Market_Report.md](deliverables/B_Roblox_Market_Report.md) | Sections 3 & 12 — Q3 2026 macro data, genre saturation & 10 market opportunities |
| **C** | [C_Competitive_Analysis_Database.md](deliverables/C_Competitive_Analysis_Database.md) | Section 3 — 44 verified Roblox experiences across all 6 market categories |
| **D** | [D_Successful_Game_Feature_Matrix.md](deliverables/D_Successful_Game_Feature_Matrix.md) | Section 4 — Python-computed 41-mechanic frequency matrix & causation audit |
| **E** | [E_Roblox_Discovery_Playbook.md](deliverables/E_Roblox_Discovery_Playbook.md) | Section 5 — Nov 2026 RFY 28-day algorithm, 9 surfaces, 19 signals & cold-start playbook |
| **F** | [F_Viral_Game_Case_Studies.md](deliverables/F_Viral_Game_Case_Studies.md) | Section 6 — 12 forensic 16-point case studies, 10 failed clones & survivorship audit |
| **G** | [G_Retention_and_Monetization_Framework.md](deliverables/G_Retention_and_Monetization_Framework.md) | Sections 7, 8, 9 & 10 (Qualitative) — Psychology, 9 timescales, loops, social & Paid Random Items compliance |
| **H** | [H_Preliminary_Game_Idea_Evaluation.md](deliverables/H_Preliminary_Game_Idea_Evaluation.md) | Section 13 — Critical post-research evaluation of [GameIdea.txt](../GameIdea.txt) |
| **I** | [I_Alternative_Game_Concepts.md](deliverables/I_Alternative_Game_Concepts.md) | Section 14 — 6 original concepts (`C1`–`C6`) × 20 required specifications |
| **J** | [J_Concept_Decision_Matrix.md](deliverables/J_Concept_Decision_Matrix.md) | Section 15 — Weighted scoring matrix (`C0`–`C6`) & 5-profile sensitivity analysis |
| **K** | [K_Prototype_Roadmap_Validation_and_Risks.md](deliverables/K_Prototype_Roadmap_Validation_and_Risks.md) | Sections 16–19 — Solo MVP roadmaps, 11 validation experiments, 6 gates, `AnalyticsService` & 19-risk pre-mortem |
| **L** | [L_Financial_Feasibility_Report.md](deliverables/L_Financial_Feasibility_Report.md) | Section 10 (Quantitative) — 9-scenario USD/PHP financial model, PH Tax Treaty Art. 13 & Ad Credit arbitrage |
| **M** | [M_Launch_and_Growth_Strategy.md](deliverables/M_Launch_and_Growth_Strategy.md) | Section 11 — 6-stage launch pipeline, packaging/thumbnail testing, 3 budget UA tiers & Go/Fix/Kill matrix |
| **N** | [N_Founder_Cheat_Sheet_and_Recommendations.md](deliverables/N_Founder_Cheat_Sheet_and_Recommendations.md) | Deliverable N (7 cheat-sheet lists) + Section 22 (Direct answers to all 12 strategic questions) |

---

## Machine-Readable Datasets & Verified Python Tooling

### Datasets (`research/data/`)
- [games_database.csv](data/games_database.csv) — 44 deduplicated verified experiences × 24 structured columns (dated `2026-11-22`).
- [feature_matrix.csv](data/feature_matrix.csv) — 44 experiences × 41 binary mechanic presence flags.
- [decision_matrix.json](data/decision_matrix.json) — 7 scored concepts (`C0`–`C6`) across Section 15's 9 weighted criteria with evidence/confidence tags.
- [financial_assumptions.json](data/financial_assumptions.json) — 9 financial scenarios across 3 resource tiers using Nov 2026 DevEx (`$0.0038`/`$0.0054`) and BSP/BAP/Wise FX (`₱63.75/USD`).
- [sources_registry.json](data/sources_registry.json) — 29 tiered primary, secondary, and supplementary source records (`S01`–`S29`).

### Reproducible Scripts & Unit Tests (`research/scripts/` & `research/tests/`)
- [common.py](scripts/common.py) — Shared constants, 7-tier evidence enum, and safe I/O helpers.
- [validate_research_data.py](scripts/validate_research_data.py) — Schema/invariant validator and cohort frequency calculator.
- [financial_model.py](scripts/financial_model.py) — Deterministic DevEx, Marketplace cut, break-even, ROAS, and USD/PHP financial engine.
- [decision_matrix.py](scripts/decision_matrix.py) — Weighted concept scorer and 5-profile sensitivity engine.
- [compile_report.py](scripts/compile_report.py) — Assembles Deliverables A–N + Sources Appendix into [Roblox_Deep_Research_Report.md](../Roblox_Deep_Research_Report.md).
- Unit Test Suite (`15` tests): [test_validate_research_data.py](tests/test_validate_research_data.py), [test_financial_model.py](tests/test_financial_model.py), [test_decision_matrix.py](tests/test_decision_matrix.py), [test_compile_report.py](tests/test_compile_report.py).

---

## Section 20 Evidence & Bias-Control Methodology
1. **Blind-First Architecture:** All Phase 1 web research (6 parallel agents, >180 targeted queries) and Phase 2 synthesis (`Deliverables B–G`) executed **strictly blind to `GameIdea.txt`** to eliminate confirmation bias.
2. **7-Tier Evidence Taxonomy:** Major claims throughout all deliverables are classified using Section 20's exact scale: `[Officially confirmed]`, `[Strongly supported by evidence]`, `[Observational correlation]`, `[Developer-reported experience]`, `[Reasonable inference]`, `[Speculative hypothesis]`, and `[Unknown]`.
3. **Zero Fabrication Rule:** Unverifiable third-party private metrics (such as official Creator Hub average session durations, exact 30-day visit deltas, proprietary RFY neural weights, or undisclosed publisher ad rev-share %) are explicitly recorded as `Unknown`.
