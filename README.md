# Mingusbreath

Single-player 3D open-world game built in Godot 4.6. Procedurally generated islands separated by open ocean, use-based skill leveling, melee/block combat, boats for island-to-island travel.

## Tech

- **Engine**: Godot 4.6 stable — Forward+ renderer
- **Language**: GDScript (C# / GDExtension only if profiler demands it)
- **World**: 4 km × 4 km ocean with 8 deterministically-placed authored islands, distance-streamed around player
- **Save**: Binary via `FileAccess` + `var_to_bytes`, atomic write (write-temp → rename), version-tagged header

## Setup

1. Open `project.godot` in `Godot_v4.6.2-stable_win64.exe`
2. Press F5

No external dependencies. All ten autoloads register on startup from `globals/`.

## Project Structure

```
globals/        Autoload singletons (GameState, EventBus, SaveSystem, SkillManager, etc.)
data/           .tres Resources — items, recipes, biomes, enemies, skills, ships
scripts/        GDScript logic (player, combat, ai, ships, world, crafting, inventory, ui, util)
scenes/         .tscn files mirroring scripts/ layout
shaders/        Water, foliage wind, toon
assets/         Models, textures, sfx, music
tests/          GUT tests (save + gen systems)
docs/planning/  Architecture doc + phase plans
```

## Systems

| System | Status |
|--------|--------|
| Project skeleton + 9 autoloads + save round-trip | Phase 1 — done |
| Player controller + camera + melee combat + test island | Phase 2 |
| Skill curves + inventory + basic boat | Phase 3 |
| Combat depth (block/dodge/stamina) + real enemy AI | Phase 4 |
| Time of day + premade-island streaming + biomes + per-island deltas + save schema v2 | Phase 5 — done |
| Foliage, real ocean shader, naval combat, biome spawn tables | Phase 6+ |

## Global Services

| Autoload | Role |
|----------|------|
| `GameState` | World seed, paused state, run-wide flags |
| `EventBus` | Decoupled project-wide signals |
| `SaveSystem` | Atomic snapshot/restore, Saveable registry |
| `TimeOfDay` | Game clock, dawn/day/dusk/night phases |
| `WorldStream` | Distance-based island load/unload around player; biome detection |
| `IslandRegistry` | Deterministic seeded island placement; runtime_id assignment |
| `BoatManager` | Tracks spawned boats; saves/restores positions across reloads |
| `SkillManager` | Per-skill XP/level tracking, level-up events |
| `InventoryRegistry` | Lookup table of all `ItemDef`s by id |
| `DiscoveryLog` | Discovered map regions + crafting stations |
| `AudioDirector` | Music stems per biome/combat, sfx pool |

## Input Actions

| Context | Actions |
|---------|---------|
| Movement | `move_forward/back/left/right`, `jump`, `sprint`, `dodge` |
| Combat | `attack_light`, `attack_heavy`, `block`, `interact` |
| UI | `inventory`, `map`, `pause` |
| Boat | `throttle_up/down`, `rudder_left/right`, `fire_cannon`, `spawn_boat` |
| Debug | `reset_save` (R) — wipe save and reload scene |

## Docs

- [`docs/planning/ARCHITECTURE.md`](docs/planning/ARCHITECTURE.md) — full system design
- [`docs/planning/PHASE_1_PLAN.md`](docs/planning/PHASE_1_PLAN.md) — skeleton + autoloads
- [`docs/planning/PHASE_2_PLAN.md`](docs/planning/PHASE_2_PLAN.md) — player + combat
- [`docs/planning/PHASE_3_PLAN.md`](docs/planning/PHASE_3_PLAN.md) — skills + inventory + boat
- [`docs/planning/PHASE_4_PLAN.md`](docs/planning/PHASE_4_PLAN.md) — combat depth + enemies
- [`docs/planning/PHASE_5_PLAN.md`](docs/planning/PHASE_5_PLAN.md) — TimeOfDay + island streaming + biomes
