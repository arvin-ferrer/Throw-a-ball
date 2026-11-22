# Team Create snapshot — 2026-11-23 (teammate work, preserved before any merge)

Exported read-only from the Team Create place "Throw-a-ball" when a second, parallel
implementation was found inside the same `ReplicatedStorage.Shared` / `ServerScriptService.Server`
folders our Git `main` syncs into. Nothing here was modified.

- `teammate_teamcreate_snapshot.rbxm` — the teammate's `Shared` + `Server` (includes modules not in
  Git: `Utils.CombatLogic`, `Utils.EconomyLogic`, `Utils.ArenaCycleLogic`, `Utils.PolicyLogic`,
  `Utils.ProceduralModels`, `Utils.AudioCatalog`, `Utils.MathUtil`, `Configs.EggConfigs`,
  `Configs.TraitConfigs`, `Services.TelemetryService`).
- `teammate_assets_snapshot.rbxm` — `ReplicatedStorage.Assets` (2,827 Part-built models).

In the place: the teammate's folders are untouched and active; our `main` copy is parked as
`Shared_OursPendingRemoval` / `Server_OursPendingRemoval` (script disabled) so the two servers
never run together. Next step: merge both lines in Git, then a single sync.
