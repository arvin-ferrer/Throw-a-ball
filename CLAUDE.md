# Claude Code Project Instructions (`CLAUDE.md`)

Follow all shared architecture, security, and cross-platform collaboration rules in [AGENTS.md](./AGENTS.md) and the canonical design in [docs/GameIdea_Evolved_GDD.md](./docs/GameIdea_Evolved_GDD.md).

## Claude-Specific Responsibilities
- Act as **Lead Roblox Systems Engineer**: architect and implement server-authoritative Luau services (`game/src/server/Services/`), DataStore/ProfileStore persistence, 3-phase Arena state machines, atomic Dual-Currency (`Coins` + `Boss Gems`) transactions, and `PolicyService` gating.
- Load relevant `scenario-roblox-*` skills from `.claude/skills/` before writing networking, combat, persistence, or monetization code.
- After implementing or modifying any Luau service, run `python scripts/check.py` and audit for race conditions, remote-spam exploits, and state-desync bugs.
