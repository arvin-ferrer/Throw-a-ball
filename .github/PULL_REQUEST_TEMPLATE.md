## Summary
<!-- Briefly describe what this PR adds, fixes, or changes. -->

## Type of Change
- [ ] Gameplay / Luau Service (`game/src/`)
- [ ] Unit Tests (`game/tests/` or `scripts/tests/`)
- [ ] 3D Asset / Blender Pipeline (`game/assets/`)
- [ ] Documentation / GDD (`docs/`)
- [ ] Tooling / Workflows (`scripts/`, `workflows/`, `.github/`)

## Verification Checklist
- [ ] Aligns with [docs/GameIdea_Evolved_GDD.md](../docs/GameIdea_Evolved_GDD.md)
- [ ] `python scripts/check.py` passes locally (StyLua, Selene, Lune tests, Rojo build)
- [ ] Server-authoritative invariants preserved (no client-trusted damage, Cash Pads, offline cap, or 5s Egg claims)
- [ ] PvP damage strictly restricted to `Phase == "PvP_EggScramble"` inside locked Boss/PvP rooms
- [ ] Paid Random Items (`PolicyService`) rules respected (if touching monetization/shop)
- [ ] Zero hardcoded local paths (`/home/...`, `C:\Users\...`) introduced
- [ ] Attached preview PNGs from `game/assets/renders/` (if adding/updating 3D assets)
