# Mingusbreath — High-Level Architecture Plan

## Context

A single-player 3D Godot 4.6 game with Valheim-flavored mechanics: use-based skill leveling, melee/ranged/block combat, no building, set in a huge **contiguous** procedurally-generated world of biome-themed islands separated by vast oceans. Travel between islands is via craftable boats with arcade-style steering (Wind Waker-ish) and naval combat. Single save slot, single-player only. Project lives at `C:\Users\chris\OneDrive\Desktop\mingusbreath` and is opened with the existing Godot 4.6 editor at `C:\Users\chris\OneDrive\Desktop\Stuff\New folder\Godot_v4.6.2-stable_win64.exe`.

The architecture is optimized for: (1) smooth streaming of a large contiguous world without loading screens, (2) data-driven content so adding items/recipes/enemies is editor-only, (3) deterministic procedural generation from a single world seed, and (4) a small, well-defined set of global services so systems stay decoupled.

---

## Tech Choices

- **Engine**: Godot 4.6 stable (already on disk).
- **Language**: GDScript for everything by default. Reach for C# / GDExtension only if a profiler tells us a hot path needs it (likely candidates: chunk meshing, noise sampling).
- **Rendering**: Forward+ renderer (default) for stylized low-poly with directional shadows and good water shaders.
- **Input**: Godot's InputMap with rebindable actions, controller-aware.
- **Save format**: Binary via `FileAccess` + `var_to_bytes` (compact, version-tagged header). JSON for debug dumps only.
- **World units**: 1 Godot unit = 1 meter. All distances, chunk sizes ("128 m chunks"), and movement speeds in this doc use meters.

---

## InputMap (Canonical Action Names)

Action names are pinned now so combat, movement, UI, and sail systems all reference the same identifiers and we avoid a later rename pass. All actions are rebindable in the settings UI.

- **Movement:** `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `dodge`
- **Combat:** `attack_light`, `attack_heavy`, `block`, `interact`
- **UI:** `inventory`, `map`, `pause`
- **Boat mode:** `throttle_up`, `throttle_down`, `rudder_left`, `rudder_right`, `fire_cannon`

Default keyboard + controller bindings ship in `project.godot`; the settings screen (later phase) edits the same map.

---

## Project Layout

```
mingusbreath/
├── project.godot
├── globals/                 # Autoloads — see "Global Services"
├── data/                    # .tres Resources — content, no logic
│   ├── items/               # ItemDef
│   ├── recipes/             # RecipeDef
│   ├── biomes/              # BiomeDef (spawn tables, foliage, palette)
│   ├── enemies/             # EnemyDef
│   ├── skills/              # SkillDef (xp curve, multipliers)
│   └── ships/               # ShipDef
├── scripts/
│   ├── world/               # generation, streaming, chunks
│   ├── player/              # controller, camera, state machine
│   ├── combat/              # hitboxes, damage, projectiles
│   ├── ai/                  # enemy + ship AI state machines
│   ├── ships/               # boat controller, buoyancy, cannon
│   ├── crafting/            # station, recipe resolver
│   ├── inventory/           # inventory + equipment containers
│   ├── ui/                  # screens, HUD, menus
│   └── util/                # math, pooling, signals helpers
├── scenes/                  # .tscn files mirroring scripts/ layout
├── shaders/                 # water, foliage wind, toon
├── assets/                  # models, textures, sfx, music
└── tests/                   # GUT tests (optional, recommended for save+gen)
```

Mirroring `scripts/` and `scenes/` keeps file navigation predictable.

---

## Global Services (Autoloads)

Each is a singleton node loaded at startup. Kept small and orthogonal:

| Autoload | Responsibility |
|---|---|
| `GameState` | Run-wide flags, current world seed, paused state |
| `EventBus` | Project-wide signals (`item_picked_up`, `enemy_killed`, `skill_xp_gained`, `station_discovered`, `boss_defeated`, `time_phase_changed`). Systems emit/listen here instead of holding refs to each other. |
| `SaveSystem` | Snapshot/restore of all persisted state; one slot, atomic write (write-temp-then-rename) |
| `TimeOfDay` | Game-clock ticking, current phase (dawn/day/dusk/night), drives sun + spawn tables |
| `WorldStream` | Chunk loader/unloader around player, owns the active chunk grid |
| `SkillManager` | Tracks per-skill xp/level, applies multipliers, emits level-ups |
| `InventoryRegistry` | Lookup table of all `ItemDef`s by id (loaded once from `data/items/`) |
| `DiscoveryLog` | Discovered map regions + discovered crafting stations |
| `AudioDirector` | Music stems for biome/combat, sfx pool |

Rule: autoloads never reach into scenes; scenes call autoloads or emit on EventBus.

---

## World System

**Goal:** "Huge, contiguous, no loading screens" with reasonable memory use.

- **World seed**: a single 64-bit int. Everything generative (island layout, biome assignment, spawns, station placement, boss locations) derives from it deterministically — never store generated content in the save, only *modifications* to it.
- **Chunked streaming** in a flat XZ grid. Starting target: **128 m chunks**, active radius **5–7 chunks** around player (tune later by profiling).
- **Two layers** per chunk:
  1. **Ocean layer**: a cheap GPU water plane that always exists and just follows the player horizontally — one mesh, animated shader, no per-chunk cost.
  2. **Island layer**: only chunks whose seed-derived "is-land" mask is non-empty actually generate terrain meshes. Most chunks are empty water, costing nothing.
- **Island generation pipeline** (per land chunk):
  1. Sample low-frequency noise to decide if this chunk is part of an island and which island id.
  2. Heightmap from layered FastNoiseLite (continent + detail).
  3. Biome assignment from per-island temperature/humidity noise → `BiomeDef` resource.
  4. Visual mesh: build terrain via Godot's `SurfaceTool` / `ArrayMesh`. Collider: a `HeightMapShape3D` (or trimesh) generated from the same heightmap — the two are complementary, not alternatives.
  5. Scatter foliage/rocks via deterministic Poisson disk sampling, rendered as `MultiMeshInstance3D` per chunk for draw-call efficiency.
  6. Place crafting stations and boss spawn anchors deterministically per island.
- **Modifications layer**: the save records *deltas* per chunk — felled trees, mined rocks (with respawn timestamps), dropped items, killed boss flags. On chunk load, regenerate from seed then apply deltas.
- **LOD**: distant chunks render only terrain + impostor billboards; near chunks get full foliage + colliders. Colliders only on active radius.

**Critical scripts to create:**
- `globals/world_stream.gd` (autoload)
- `scripts/world/chunk.gd`
- `scripts/world/island_generator.gd`
- `scripts/world/biome_def.gd` (Resource)
- `scripts/world/foliage_scatter.gd`

---

## Player & Combat

- **Controller**: `CharacterBody3D` + `SpringArm3D` third-person camera. Stylized low-poly — toon shader on character, rim light optional.
- **State machine** (`scripts/player/states/`): Idle, Run, Sprint, Jump, Fall, Swim, Block, Attack, Dodge, Sail (when mounted on a boat). One state at a time; transitions are explicit.
- **Stats**: HP, Stamina, Hunger (Valheim-ish food buffs). Stamina drains on sprint/jump/attack/block-hit.
- **Melee**: Each weapon scene has an `Area3D` hitbox (per your call). Animation track toggles `monitoring` on/off during the active frames of the swing. Hits emit `EventBus.damage_dealt` carrying attacker, target, weapon, skill_id.
- **Ranged**: Bow draws a charge → spawns an arrow `RigidBody3D` (or raycast for fast/cheap arrows) with damage payload. Drawing costs stamina, charge level scales damage.
- **Block**: While blocking, incoming damage is reduced by block-skill multiplier and consumes stamina. Parry window if block is timed.
- **Damage flow**: `Hurtbox` (Area3D on enemy/player) receives signal from hitbox, asks `CombatResolver` for final damage given resistances + skill multipliers, applies it, emits death event if HP ≤ 0.

**Critical scripts:**
- `scripts/player/player.gd`, `player_camera.gd`, `states/*.gd`
- `scripts/combat/hitbox.gd`, `hurtbox.gd`, `combat_resolver.gd`, `projectile.gd`

---

## Skill System

Pure use-based, no XP loss on death. Skills:

> Swords, Axes, Clubs, Polearms, Knives, Bows, Unarmed, Block, Sneak, Run, Jump, Swim, Sail, Woodcutting, Mining, Cooking, Fishing

- Each skill is a `SkillDef` resource: id, display name, xp curve (array of thresholds or formula), per-level effect (damage mult, stamina mult, gather speed mult, etc.).
- `SkillManager` holds `{skill_id: {level: int, xp: float}}`.
- Hooks: combat resolver calls `SkillManager.add_xp(weapon_skill, amount)`; movement controller adds Run/Jump/Swim XP over time spent in those states; gathering tools add Woodcutting/Mining; cooking station awards Cooking; etc.
- Level-up → `EventBus.skill_leveled` → HUD toast + audio sting.

---

## Crafting (Discoverable Stations)

- Each `CraftingStation` scene has a `station_type` (forge, workbench, cooking pit, alchemy bench, etc.) and a list of `RecipeDef` resources keyed to that type.
- Stations are placed by `island_generator.gd` at deterministic anchor points per island (one or two per island, biome-appropriate).
- A station is **undiscovered** until the player enters its proximity radius once → `DiscoveryLog.discover_station(id)` → persists to save.
- Crafting UI opens on interact when adjacent; recipes filter to (a) what this station supports, (b) skills high enough, (c) ingredients in inventory.
- No portable crafting (per your call). No building.

**Critical scripts:** `scripts/crafting/crafting_station.gd`, `recipe_def.gd`, `crafting_screen.gd`.

---

## Boats & Naval Combat

- **Boat scene**: `RigidBody3D` with a custom buoyancy script sampling water height (matches the ocean shader's wave function) at a few hull points. Arcade steering — throttle + rudder, no wind.
- **Mounting**: interact prompt while near boat → camera attaches to boat-relative spring arm, player input drives boat instead of character.
- **Boat inventory**: separate inventory container (a chest on the boat). Persists with the boat.
- **Hull HP**: takes damage from cannons / sea creatures; sinking destroys cargo.
- **Cannons / weapons**: forward-mounted; fire on input → projectile `RigidBody3D` with arc trajectory. Hits another ship's hurtbox.
- **Wandering enemy ships**: roam ocean using simple heading-based AI (no Navigation3D needed — sea is open). Detect player at range, pursue, fire cannons, retreat at low HP. Soft-tier scaled to distance from origin.

**Critical scripts:** `scripts/ships/boat.gd`, `buoyancy.gd`, `boat_camera.gd`, `cannon.gd`, `scripts/ai/wandering_ship_ai.gd`.

---

## Enemy AI

- **Biome-locked land enemies**: each `BiomeDef` lists day-spawn and night-spawn tables. Spawner per chunk picks from the right table based on `TimeOfDay` phase. Despawn when far from player.
- **State machine** per enemy: Idle → Patrol → Sense → Chase → Attack → Flee/Return. Senses are sight-cone + hearing-radius.
- **Stats** scale by biome tier (meadows weakest, deeper/farther biomes stronger) — soft strength gating, no boss-kill flags required to enter biomes.
- **Bosses**: one deterministic boss anchor per major biome. Bosses don't unlock anything mechanically; they drop strong gear/trophies that *let* the player survive harder biomes — gating is via player power, not flags.

---

## Time of Day

- `TimeOfDay` autoload ticks game-minutes (e.g. 1 real second = N game minutes, configurable).
- Drives a `DirectionalLight3D` rotation + `WorldEnvironment` sky/ambient via curves keyed to time.
- Emits `time_phase_changed` (dawn/day/dusk/night) — spawners and AudioDirector listen.
- No seasons, no weather (per your call).

---

## Save System

Single slot. Atomic save: write to `save.tmp`, fsync, rename over `save.dat`.

**Persisted state** (per your list):
- World seed + game version
- Player: position, rotation, HP/stamina/hunger, inventory, equipment, skill table
- **Ship states**: per ship — position, rotation, HP, inventory, anchored flag
- **Inventory** (player) and **ship inventory** (per ship)
- **Discovered map regions** (chunk ids the player has entered)
- Discovered crafting stations
- Per-chunk modification deltas (felled trees, mined rocks with respawn timer, dropped items, dead-boss flags)
- Time of day clock
- Quest/journal state (if added later — leave room in schema)

Auto-save on: sleep, fast-travel (none for now, but reserved), quit-to-menu, periodic interval (e.g. every 5 game-minutes).

**Schema versioning**: header `{version: int, seed: int}`. Migrations are functions keyed by version.

**Critical script:** `globals/save_system.gd` + small `Saveable` interface (`save_data() -> Dictionary`, `load_data(d)`) on player/ship/chunk-delta-store.

---

## UI

- **HUD**: HP/stamina/hunger bars, hotbar (8 slots), compass, time, biome name on entry.
- **Inventory + Equipment**: drag-drop grid, equipment slots, tooltips from `ItemDef`.
- **Crafting screen** (modal at station): recipe list, ingredient counts, craft button.
- **Map screen**: shows only discovered chunks; markers for discovered stations.
- **Skill screen**: per-skill bar with level + XP-to-next.
- **Pause + Settings**: graphics, audio, keybinds.

All screens scenes under `scenes/ui/`, scripts under `scripts/ui/`. Theme resource shared across.

---

## Performance Practices Baked In From Day One

- `MultiMeshInstance3D` for foliage/rocks per chunk.
- Object pools for: arrows, cannonballs, particle one-shots, popup damage numbers.
- Colliders only on active-radius chunks; distant chunks visual-only.
- Single ocean mesh that follows the player; ocean is shader-driven, not geometry-driven.
- Profile early: `--debug-collisions`, the built-in profiler, and `Performance.get_monitor()` checks once chunks stream.

---

## Verification (How We'll Know It Works)

1. Open `project.godot` in the Godot 4.6 editor on disk.
2. Press F5 — spawn on starter (meadows) island.
3. Walk → Run skill ticks. Chop a tree → Woodcutting + Axes tick. Tree felling persists across reload.
4. Find a forge/workbench → it gets marked discovered → reopen game, still discovered.
5. Craft a basic item at the station; it appears in inventory.
6. Walk to shore, board boat, sail to next island; ocean is contiguous, no load screen.
7. Engage a wandering ship — cannon fire damages both. Sink it.
8. Wait until night → night spawn table activates; different enemies appear.
9. Quit and relaunch → player position, ship position + cargo, HP, skills, discovered regions, modified chunks, time of day all restored.
10. Stress test: walk in one direction for several minutes — chunks stream in/out without stalls; framerate stable.

---

## Implementation Order (Recommended Sequencing)

To avoid building a tower that won't compile end-to-end, I'd build vertical slices:

1. Project skeleton + all ten autoload stubs registered + EventBus signals enumerated + SaveSystem round-tripping one dummy field.
2. Player controller + third-person camera on a flat test plane.
3. World streaming with a dumb flat heightmap (no biomes yet) — prove chunks load/unload around player.
4. Island generator + biome assignment → real terrain on chunks.
5. Combat: hitbox/hurtbox, one melee weapon, one enemy.
6. Skill system + first three skills (Swords, Run, Woodcutting).
7. Inventory + first crafting station + first recipe.
8. Boat + ocean shader + basic sailing.
9. Cannon + naval combat + wandering ship AI.
10. TimeOfDay + day/night spawn tables + boss anchor.
11. Persistence pass: every system implements `Saveable`.
12. UI polish: map, skills screen, settings.

Each step should be playable on its own before moving on.

---

## Files to Create First (Phase 1 Skeleton)

- `mingusbreath/project.godot` (create via Godot editor's New Project dialog → Forward+ renderer)
- `mingusbreath/globals/event_bus.gd`
- `mingusbreath/globals/game_state.gd`
- `mingusbreath/globals/save_system.gd`
- `mingusbreath/globals/time_of_day.gd`
- `mingusbreath/globals/world_stream.gd`
- `mingusbreath/globals/skill_manager.gd`
- `mingusbreath/globals/inventory_registry.gd`
- `mingusbreath/globals/discovery_log.gd`
- `mingusbreath/globals/audio_director.gd`
- `mingusbreath/scenes/main.tscn` (root scene)
- `mingusbreath/scenes/player/Player.tscn` + `scripts/player/player.gd`
- `mingusbreath/scenes/world/Chunk.tscn` + `scripts/world/chunk.gd`
- `mingusbreath/scripts/world/island_generator.gd`

All ten autoloads are registered in `project.godot` from the start so any system can reference them safely.
