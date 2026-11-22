# Roblox Deep Market Research & Product Validation (`Throw-a-ball`)

Evidence-based late-2026 Roblox market discovery, discovery algorithm analysis, competitive intelligence (`n = 44` verified experiences), concept evaluation, sensitivity decision modeling, and USD/PHP financial feasibility research anchored to a solo indie developer.

**Collection Date:** `2026-11-22`

---

## Start Here

- **[Visual Results Summary — Markdown](Research_Results_Visual_Summary.md)** | **[Executive PDF (8 pages)](Roblox_Research_Results_Visual_Summary.pdf)** — Executive scorecard, 6 high-DPI Matplotlib charts, and architecture/roadmap diagrams.
- **[C2: Egg Heist: Boss Vault — Game Design Document (Markdown)](C2_Egg_Heist_Game_Design_Document.md)** | **[GDD PDF](C2_Egg_Heist_Game_Design_Document.pdf)** — Complete features, gameplay loop, boss/orb specs, ethical monetization, and 10-day solo prototype blueprint for the `#1` ranked reimagined concept (`8.43 / 10`).
- **[Compiled Master Research Report (44,477 words)](Roblox_Deep_Research_Report.md)** — Complete single-file report containing Deliverables A–N, Section 22's 12 direct strategic recommendations, and the 29-source Appendix.
- **[Modular Research Vault Index](research/README.md)** — Individual Markdown deliverables (`A`–`N`), CSV/JSON datasets, Python modeling/validation scripts, and `unittest` suite.

![Concept Decision Matrix & Sensitivity Spread](research/charts/01_concept_decision_scores.png)

---

## Repository Structure

```text
.
├── C2_Egg_Heist_Game_Design_Document.md     # Complete GDD for #1 ranked C2 concept
├── C2_Egg_Heist_Game_Design_Document.pdf    # Exported GDD PDF
├── GameIdea.txt                             # Original preliminary brainstorm
├── Research.txt                             # Full 22-section research brief
├── Research_Results_Visual_Summary.md       # Executive visual results & charts
├── Roblox_Research_Results_Visual_Summary.pdf # Exported 8-page executive visual PDF
├── Roblox_Deep_Research_Report.md           # Compiled single-file master report
└── research/
    ├── README.md                            # Modular deliverables index
    ├── charts/                              # 10 verified 180-DPI PNG charts & diagrams
    ├── data/                                # Audited CSV/JSON datasets (44 games x 41 mechanics)
    ├── deliverables/                        # Deliverables A through N
    ├── scripts/                             # Math/validation, charts, diagrams & PDF builder
    └── tests/                               # 19 automated unittest cases
```

## Reproducing Models, Charts & Tests

```bash
python3 -m unittest discover -s research/tests -v
python3 research/scripts/validate_research_data.py --data-dir research/data --print-frequencies
python3 research/scripts/decision_matrix.py --input research/data/decision_matrix.json --markdown
python3 research/scripts/financial_model.py --input research/data/financial_assumptions.json --markdown
python3 research/scripts/generate_charts.py --data-dir research/data --out-dir research/charts
```
