# Game Workspace (`game/`)

Rojo + Rokit strict-Luau workspace and 3D asset pipeline for **Ball Brawl: Boss Eggs**.

## Source Layout (`src/`)

| Path | Roblox Target | Owns |
| :--- | :--- | :--- |
| `src/shared/Configs/` | `ReplicatedStorage/Shared/Configs` | Pure data & math tables (`EconomyConfigs`, `BiomeConfigs`, `PetConfigs`, `TraitConfigs`, `EggConfigs`). |
| `src/shared/Net/` | `ReplicatedStorage/Shared/Net` | Typed RemoteEvent / RemoteFunction contracts. |
| `src/shared/Utils/` | `ReplicatedStorage/Shared/Utils` | Pure Luau helpers shared by server, client, and Lune tests. |
| `src/server/Services/` | `ServerScriptService/Server/Services` | Server-authoritative services (`ArenaCycleService`, `CombatService`, `DataService`, `EconomyService`, `PetIncomeService`, `PolicyGuardService`, `PlotService`, `BossAIService`). |
| `src/client/Controllers/` | `StarterPlayerScripts/Client/Controllers` | Input, camera, Ball Throw controller, Cash Pad feedback, Arena HUD, Hatch VFX. |
| `src/client/UI/` | `StarterPlayerScripts/Client/UI` | Mobile-first HUD, Opt-In modals, Codex, Shop & `PolicyService` odds display. |
| `tests/` | *(Lune offline runtime)* | Fast `*.spec.luau` unit tests executed by `python scripts/check.py`. |

## Asset Layout (`assets/`)

| Path | Contents |
| :--- | :--- |
| `assets/blender/` | Procedural & cleanup Blender `bpy` Python scripts (run via `python scripts/blender_run.py`). |
| `assets/imports/` | External or AI-generated raw 3D imports awaiting cleanup/rigging (e.g. `Pyraxis.glb`). |
| `assets/exports/` | Studio-ready `.glb` / `.fbx` meshes exported from Blender. |
| `assets/renders/` | Preview & turntable PNG renders for Visual QA. |
| `assets/audio/` | Sound effects and music cues. |
| `assets/ui/` | 2D icons, badges, and 16:9 Home thumbnail art. |

## Common Commands

```bash
# Install pinned tools from rokit.toml
rokit install

# Run full quality gate from repo root
python ../scripts/check.py

# Live sync into Roblox Studio (never point two teammates' rojo serve at one Team Create place)
rojo serve
```
