# Phase 5 Plan — Time of Day + Premade-Island Streaming + Biomes

## Context

Phases 1–4 shipped: skeleton + autoloads + atomic save (Phase 1), playable character + melee + test island (Phase 2), skill curves + inventory + basic boat (Phase 3), and the combat-depth pass (block/dodge action states, husk enemy AI, and HP/stamina bars). The current dev scene `scenes/dev/test_island.tscn` hardcodes a single 120 m × 120 m heightmap island over a 600 m × 600 m flat water plane and spawns the player at `(0, 15, 0)`.

Phase 5 turns the project from "one hand-placed island" into a **multi-island, day/night world** where:

- A handful of **premade islands** (hand-curated scenes — initially seeded by the IslandGenerator output but stored as `.tscn` files so they can be edited/extended by hand) are scattered at deterministic random positions across one very large ocean.
- The player streams these islands in/out by **distance to player** as they sail or walk near them — not by a chunk grid.
- Each premade island carries its own `BiomeDef` reference (no per-chunk biome assignment, no biome-noise stripes through islands).
- A game clock ticks the sun across the sky and emits `time_phase_changed`.

Explicit anti-goal: no Valheim-style fully-procedural island shapes. Islands are *authored content* placed at *seeded random positions*. Same `world_seed` → same placement; new biomes/islands are added by dropping new `IslandDef` resources into `data/islands/`, not by tuning continent noise.

This rewrites the original Phase 5 plan (chunk-grid streaming + per-chunk biome noise) — see § "Plan-Revision Note" at the bottom for what was dropped and why.

This is arch [Implementation Order](../../docs/planning/ARCHITECTURE.md) step 3 (streaming) and step 10 (TimeOfDay), with biome assignment landing as a per-island authored property rather than a continent-noise function.

**Naval combat, ranged combat, biome-keyed spawn tables, ocean shader/buoyancy, foliage scatter, and crafting all stay deferred.** Phase 5's biome system records the active biome (= biome of the nearest enclosing island, else "ocean") and recolours terrain via authored materials — it does **not** run biome-locked spawners (those depend on Phase 4 enemy AI being complete) and does **not** rewrite the boat (that is Phase 8).

---

## Deliverables

After F5 from a fresh save:

1. **Big ocean.** One large `MeshInstance3D` water plane parented to a follower node that tracks the player's XZ. World extents pinned at `WORLD_SIZE_M = 4096.0` (4 km × 4 km). Ocean is one mesh, no per-chunk water. Placeholder shader (flat blue with a slow uv-pan tint) — real ocean shader is Phase 8.
2. **Premade island library.** A small set of authored `IslandDef` resources (4 ship in this phase: meadows, forest, tundra, desert), each pointing at a `PackedScene` (`scenes/islands/island_<biome>_01.tscn`). Initial scenes are produced by running `IslandGenerator.generate` once per biome at edit-time, saving the resulting `ArrayMesh` and `HeightMapShape3D` to `.tres` resources, then committing those resource files alongside the island scene. After Phase 5, an artist can hand-edit any island scene without rerunning generation.
3. **Deterministic island placement.** `IslandRegistry` autoload places `N = 8` islands at random positions inside a centred `WORLD_SIZE_M` square. RNG seeded from `GameState.world_seed`. Same seed → identical placement (positions + rotations + which `IslandDef` goes where). Min distance between any two island centres = `island_a.footprint_radius + island_b.footprint_radius + ISLAND_SPACING_BUFFER_M (= 80 m)`. The starter island (Meadows variant) is always pinned at world origin so spawn is predictable; the other 7 are seeded-random.
4. **Distance-based island streaming.** `IslandStream` autoload watches player position. For each placed island, computes distance from player to island centre. If distance ≤ `island.footprint_radius + LOAD_BUFFER_M (= 200 m)`, instance the island scene (once). If distance > `island.footprint_radius + UNLOAD_BUFFER_M (= 400 m)`, free the instance. Hysteresis between load/unload prevents thrash.
5. **Spawn flow.** Player spawns at the starter (Meadows) island's `SpawnAnchor` node — a `Node3D` child placed in the editor inside `scenes/islands/island_meadows_01.tscn` at a sane standing position. On a fresh save, world load instances the starter island first, then teleports the player to its anchor.
6. **Biomes (4 starter biomes).** Meadows, Forest, Tundra, Desert. Each is a `BiomeDef` resource that drives terrain vertex colour (single `StandardMaterial3D` palette swap on the island's mesh), an entry-banner `display_name`, and an optional fog/ambient tint applied to `WorldEnvironment` while the player is inside that island's biome zone. Phase 5 reads only the colour + palette + entry-banner + tint fields — `spawn_table` and `music_stem` are reserved-not-yet-used.
7. **Biome detection + entry banner.** "Active biome" = biome of the *nearest* island whose footprint the player is inside (i.e. distance ≤ `footprint_radius`); else `&"ocean"` (pseudo-biome). When the active biome changes, HUD shows a 2-second fade-in/fade-out banner with the new biome's `display_name`. Reuses the `SkillToast` queue pattern.
8. **TimeOfDay live.** A configurable `minutes_per_real_second` (default 1.0 — i.e. 1 game-minute per real second, full 24 game-hour day = 24 real minutes) ticks `game_minutes`. A `DirectionalLight3D` ("Sun") rotates around the world-X axis based on `game_minutes`. `WorldEnvironment` ambient + sky tint interpolates between four colour keys (dawn, day, dusk, night). `phase` transitions trigger `EventBus.time_phase_changed(new_phase)` exactly once per crossing.
9. **TimeOfDay persists.** `game_minutes` saves and restores. Phase recomputed from `game_minutes` on load.
10. **Per-island delta store.** New `IslandDeltaStore` keyed by `island.runtime_id` (a stable `StringName` derived from world-seed + slot index — same on every load) → `Dictionary` of deltas. Phase 5 wires the *infrastructure* — only delta type used is `&"dropped_item"` so a `scrap` pickup left on an island reappears on the same island when it streams back in. Real gather verbs (chop tree, mine rock) are Phase 6.
11. **Save round-trip preserved.** Skills, inventory, time-of-day, island deltas, player position (+ rotation) all persist. Player position is restored *after* the island under them streams in (deferred apply via `world_loaded` signal).
12. **Old test_island retired.** Production main scene becomes `scenes/world/World.tscn`. Old dev scene kept under `scenes/dev/` for regression-poking but is no longer the `application/run/main_scene`.

---

## Architecture Edits (apply to `docs/planning/ARCHITECTURE.md` first)

The original Phase 5 plan's edits assumed chunk-grid streaming. This revision swaps those for island-streaming edits.

1. **Pin BiomeDef shape.** Add a new "BiomeDef Schema" subsection to §"World System":
   ```
   id: StringName
   display_name: String
   terrain_albedo: Color
   terrain_roughness: float = 0.85
   foliage_density: float = 1.0                  # reserved — Phase 6+
   fog_tint: Color = Color(1,1,1,0)              # alpha 0 = no override
   ambient_tint_day: Color = Color(1,1,1,1)
   ambient_tint_night: Color = Color(0.4,0.4,0.55,1)
   day_spawn_table: Array[StringName] = []       # reserved — Phase 6+
   night_spawn_table: Array[StringName] = []     # reserved — Phase 6+
   music_stem: AudioStream = null                # reserved — Phase 7+
   ```
2. **Add IslandDef schema.** Replace arch §"World System" — "Island generation pipeline" with the following:
   ```
   IslandDef Schema (per `data/islands/<id>.tres`):
     id: StringName                 # unique
     display_name: String
     scene: PackedScene             # scenes/islands/<id>.tscn — Node3D root
     biome: BiomeDef
     footprint_radius: float        # metres; used for placement spacing + biome detection
     placement_weight: float = 1.0  # probability weight when seeded RNG picks islands
   Each scene's root is a Node3D and contains at minimum:
     - one MeshInstance3D for the terrain (uses biome.terrain_albedo via vertex_color OR material_override)
     - one StaticBody3D + CollisionShape3D for terrain collision
     - a child Node3D named "SpawnAnchor" indicating safe stand-up position
     - optional child Node3D named "DeltaRoot" — items respawned from the delta store re-parent here
   ```
3. **Replace chunk streaming description.** Replace arch §"World System" — "Chunked streaming" + "Two layers" + "Modifications layer" + "LOD" bullets with:
   ```
   Premade-island streaming. WORLD_SIZE_M = 4096. ISLAND_COUNT = 8 (one starter + seven seeded). Islands are authored .tscn scenes referenced by IslandDef resources. IslandRegistry deterministically places islands at world load via seeded RNG with min-distance constraints from footprint_radius. IslandStream loads each island scene when player ≤ footprint_radius + LOAD_BUFFER_M (200 m), unloads at > footprint_radius + UNLOAD_BUFFER_M (400 m). The ocean is a single 4096×4096 m flat plane parented to a follower Node3D that copies player.global_position.x and z each frame (y stays at WATER_Y). Modifications persist via IslandDeltaStore keyed by island.runtime_id (stable StringName per (world_seed, slot_index)).
   ```
4. **Pin player-position persistence flow.** Add to §"Save System": `Player position is restored only after IslandStream has loaded the starter island. WorldStream emits EventBus.world_loaded once after its first-batch synchronous load completes. Player connects to world_loaded in _ready (CONNECT_ONE_SHOT) and on emit either applies a saved position (returning user) or copies global_position from the starter island's SpawnAnchor child (cold start).`
5. **Pin TimeOfDay constants.** Add: `Default minutes_per_real_second = 1.0 (24 real-min per game day). Phase boundaries: dawn=05:00–07:00, day=07:00–18:00, dusk=18:00–20:00, night=20:00–05:00. Sun pitch: -90° at midnight up to +90° at noon and back over a full game-day.`
6. **Document IslandStream public API.** Add to §"World System":
   ```
   IslandStream.player_island: IslandPlacement      # nearest enclosing, or null
   IslandStream.active_islands: Dictionary[StringName, Node3D]  # runtime_id → instance
   IslandStream.get_active_biome() -> BiomeDef      # nearest enclosing island's biome, else null (= ocean)
   signal island_loaded(placement: IslandPlacement, instance: Node3D)
   signal island_unloaded(runtime_id: StringName)
   signal world_loaded                              # one-shot, after first batch of islands settles
   ```

---

## Files to Create

### Data resources (script classes)

- `scripts/data/biome_def.gd` — `class_name BiomeDef extends Resource`. Fields per arch edit #1. `@export` every field.
- `scripts/data/island_def.gd` — `class_name IslandDef extends Resource`. Fields per arch edit #2. `@export` every field.

### Data instances (.tres)

- `data/biomes/meadows.tres` — `id=&"meadows"`, soft green `Color(0.45, 0.65, 0.30)`, `display_name="Meadows"`, fog tint alpha=0.
- `data/biomes/forest.tres` — `id=&"forest"`, deep green `Color(0.20, 0.40, 0.18)`, darker night ambient.
- `data/biomes/tundra.tres` — `id=&"tundra"`, near-white `Color(0.85, 0.88, 0.92)`, slight cool fog tint.
- `data/biomes/desert.tres` — `id=&"desert"`, sandy `Color(0.85, 0.75, 0.45)`, warm tint.
- `data/islands/island_meadows_01.tres` — IslandDef, scene = `island_meadows_01.tscn`, biome = `meadows.tres`, `footprint_radius=80`, `placement_weight=1.0`. **This one is pinned to world origin** by IslandRegistry (see Critical Notes).
- `data/islands/island_forest_01.tres` — same shape, biome = forest, `footprint_radius=70`.
- `data/islands/island_tundra_01.tres` — biome = tundra, `footprint_radius=90`.
- `data/islands/island_desert_01.tres` — biome = desert, `footprint_radius=100`.

### Authored island scenes (`.tscn`) and their baked terrain resources

For each of the 4 islands:
- `assets/islands/<id>_mesh.tres` — `ArrayMesh` resource baked from `IslandGenerator.generate(seed=<hash of island id>, size=160, height=10)` once at edit-time. Saved to disk so the runtime never re-generates.
- `assets/islands/<id>_collider.tres` — `HeightMapShape3D` resource from the same generation pass.
- `scenes/islands/<id>.tscn` — `Node3D` root named `Island`. Child `MeshInstance3D` named `Terrain` with `mesh = preload(<mesh.tres>)` and a `material_override` set to a `StandardMaterial3D` whose `albedo_color = biome.terrain_albedo` (set in editor; albedo can be overridden at runtime by IslandStream if biome ref changes — but this phase ships with the colour baked into the scene material). Child `StaticBody3D` named `Body` with a `CollisionShape3D` whose `shape = preload(<collider.tres>)`. Child `Node3D` named `SpawnAnchor` positioned at a sensible stand-up point on the terrain. Child `Node3D` named `DeltaRoot` at island origin (used as parent for delta-spawned `ItemPickup`s).

The four scene files are committed; the baked mesh/collider resources are committed alongside. After this phase, hand-editing any island scene in the editor (move terrain, add foliage, adjust spawn anchor) is fully supported and will be picked up automatically the next time IslandStream loads it.

### Globals (autoload — files exist, expand them)

- `globals/time_of_day.gd` — full implementation. (See "Critical Implementation Notes — TimeOfDay".)
- `globals/world_stream.gd` — **rename role**. The autoload registration name stays `WorldStream` for backwards compat with arch doc and existing references in test_island.gd, but its internals become `IslandStream` semantics (placement-driven, not chunk-driven). Add a one-line comment at the top of the file documenting the rename. **Do not rename the autoload entry in `project.godot`** — that breaks every existing reference.
- `globals/event_bus.gd` — add signals: `world_loaded`, `island_loaded(placement)`, `island_unloaded(runtime_id: StringName)`, `biome_entered(biome: BiomeDef)`. Confirm `time_phase_changed` already declared (it is).

### New autoload

- `globals/island_registry.gd` — **new autoload**. Registered in `project.godot` after `WorldStream`. Scans `data/islands/*.tres` at `_ready`, builds `_defs: Array[IslandDef]`, then computes the deterministic placement (`Array[IslandPlacement]`). `IslandPlacement` is a small data struct (defined inline in the registry — `class_name IslandPlacement extends RefCounted` with `def: IslandDef`, `position: Vector3`, `rotation_y: float`, `runtime_id: StringName`, `slot_index: int`).

### Scripts (world)

- `scripts/world/world_root.gd` — `class_name WorldRoot extends Node3D`. Owns the placed-island container, the ocean follower, the player, the HUD, the Sun, the WorldEnvironment. `_ready()` wires WorldStream to its container + player ref, sets TimeOfDay's sun + env refs, then waits for `EventBus.world_loaded` to apply player save-state.
- `scripts/world/ocean_follower.gd` — `class_name OceanFollower extends Node3D`. `_process(_dt)` sets `global_position = Vector3(player.global_position.x, WATER_Y, player.global_position.z)`. Exports `target: NodePath`. Holds a child `MeshInstance3D` flat plane (`PlaneMesh` size 4096×4096, subdivided 32×32) with a placeholder blue `StandardMaterial3D`.
- `scripts/world/island_placer.gd` — pure-static helper: `static place(defs: Array[IslandDef], world_seed: int, world_size_m: float, max_attempts_per_island: int = 64) -> Array[IslandPlacement]`. Implementation is rejection sampling: for each island slot, draw a candidate position via a seeded `RandomNumberGenerator` (seed = `world_seed ^ 0xA1B2C3 ^ slot_index`); check min-distance constraint against already-placed islands; if violated, redraw up to `max_attempts_per_island` times before giving up and skipping that slot (logged via `push_warning`). The starter slot (index 0) is hard-pinned to world origin and uses the IslandDef whose `id == &"island_meadows_01"` (look up by id; if absent, `push_error`).
- `scripts/world/island_runtime_id.gd` — pure-static: `static compute(world_seed: int, slot_index: int, def_id: StringName) -> StringName`. Concat into a deterministic string then `StringName(...)` it. Lets the delta store key islands stably across loads.
- `scripts/world/island_delta_store.gd` — `class_name IslandDeltaStore extends Node`. `_deltas: Dictionary[StringName, Dictionary]` keyed by `runtime_id`. Methods: `add_delta(runtime_id, type, payload)`, `get_deltas_for(runtime_id) -> Dictionary`, `remove_delta_match(runtime_id, type, payload)`, `clear_island(runtime_id)`. Implements `Saveable` (`save_data` / `load_data`). Registered with `SaveSystem` from `_ready`. Lives as a child of `WorldStream`.

### Scripts (UI)

- `scripts/ui/biome_banner.gd` — `class_name BiomeBanner extends CanvasLayer`. **Script-only**, no `.tscn` (matches existing house style: [skill_toast.gd](../../mingusbreath/scripts/ui/skill_toast.gd) and [hud.gd](../../mingusbreath/scripts/ui/hud.gd) both build their UI in `_ready` programmatically with no .tscn). Listens to `EventBus.biome_entered`. On signal: set text, fade alpha 0→1 over 0.3s, hold 1.4s, fade 1→0 over 0.3s. Queues so two crossings don't visually stack — copy the `_queue` + `_busy` + `_show_next` recursion from [skill_toast.gd:5-7,32-47](../../mingusbreath/scripts/ui/skill_toast.gd) verbatim.

### Scenes

- `scenes/world/World.tscn` — root scene. Tree:
  ```
  WorldRoot (scripts/world/world_root.gd)
    ├── IslandContainer (Node3D)        # WorldStream parents loaded islands here
    ├── OceanFollower (ocean_follower.gd)
    │     └── WaterMesh (MeshInstance3D, PlaneMesh 4096×4096)
    ├── Sun (DirectionalLight3D)        # rotated by TimeOfDay
    ├── WorldEnv (WorldEnvironment)     # tinted by TimeOfDay/biome
    └── Player (instance of scenes/player/Player.tscn)
  ```
  HUD is instantiated by `WorldRoot._ready` via `HUD.new()` (script-only — no `.tscn` exists). HUD itself spawns SkillToast + BiomeBanner + InventoryScreen children in its `_ready`.

### Modifications to existing files

- `scripts/world/island_generator.gd` — **no semantic change**, only used at edit-time now. Add a one-shot editor tool script that runs the generator and saves output to `.tres` files (see `scripts/tools/bake_islands.gd`). Runtime never calls `generate` after this phase (until Phase 6 adds new islands).
- `scripts/tools/bake_islands.gd` — **new editor tool script** (`@tool`). Run from the editor's Script panel via Run-Script (or via a temporary editor button). Iterates the 4 starter island defs, calls `IslandGenerator.generate(stable_seed_from_id, 160, 10)`, saves resulting `ArrayMesh` to `assets/islands/<id>_mesh.tres` and the `HeightMapShape3D` to `assets/islands/<id>_collider.tres` via `ResourceSaver.save`. Idempotent — re-running on the same id produces identical files because the seed is hashed from the id. Document at the top of the file: `## DO NOT run during play. Editor-time only — bakes premade island terrain to .tres resources.`
- `globals/save_system.gd` — schema bump only (constant `SCHEMA_VERSION` 1 → 2 + migration branch). Does NOT emit `world_loaded` — that's WorldStream's responsibility, after its first-batch island load.
- `scripts/player/player.gd` — implement `Saveable`. `save_data` returns `{position: <encoded>, rotation_y: float}` (HP/stamina reset on load per Phase 4 arch — don't save). `load_data(d)` stores `_pending_pos` + `_pending_rot_y`. **In `_ready` (always — both fresh and returning saves)**, `EventBus.world_loaded.connect(_on_world_loaded, CONNECT_ONE_SHOT)`. The handler applies `_pending_pos` if set, else copies `global_position` from the starter island's `SpawnAnchor` child. Register with `SaveSystem` from `_ready`.
- `scripts/ui/hud.gd` — extend [hud.gd:7-31](../../mingusbreath/scripts/ui/hud.gd) `_ready` to add `add_child(BiomeBanner.new())` after the existing `add_child(toast)` line. Match the script-only convention (no .tscn). No behavioural change to existing toasts or pickup label.
- `project.godot` — add `IslandRegistry` autoload entry; change `application/run/main_scene` to `res://scenes/world/World.tscn`.
- `scripts/dev/test_island.gd` — keep as a regression scene under `scenes/dev/`. Do not mutate.

---

## Critical Implementation Notes

### TimeOfDay

- Pin `MINUTES_PER_DAY = 1440` (24 × 60). `game_minutes: float` allowed to grow unbounded — wrap with `fmod(game_minutes, MINUTES_PER_DAY)` only when computing visuals.
- `_process(delta)`: `game_minutes += delta * minutes_per_real_second`; recompute current phase from `_phase_for(fmod(game_minutes, 1440))`; if phase changed since last tick, set `phase` and `EventBus.time_phase_changed.emit(phase)`.
- `_phase_for(min_in_day: float) -> Phase`:
  - `>= 5*60 and < 7*60` → DAWN
  - `< 18*60` → DAY
  - `< 20*60` → DUSK
  - else → NIGHT
- Sun rotation: `sun_pitch_deg = -90 + 360 * (fmod(game_minutes, 1440) / 1440)`. Apply to `Sun.rotation.x`. Yaw stays 0.
- Ambient tint interpolation: 4 keyframe colours (`tint_dawn`, `tint_day`, `tint_dusk`, `tint_night`) on `TimeOfDay`, defaults sensible. Compute current tint by linear-interp across phase boundaries; assign to `WorldEnvironment.environment.ambient_light_color`.
- Saveable: `save_data` → `{game_minutes: float}`. `load_data(d)` → `game_minutes = d.get("game_minutes", 8.0 * 60)` (default 8:00 AM on first load). Phase recomputed.
- Register with `SaveSystem` from `_ready`. Match the existing pattern in [skill_manager.gd](../../mingusbreath/globals/skill_manager.gd).

### IslandRegistry placement

- `_ready` ONLY scans `data/islands/*.tres` into `_defs: Array[IslandDef]` (mirrors the [skill_manager.gd:12-24](../../mingusbreath/globals/skill_manager.gd) `_load_defs` pattern). Does NOT compute placements — `GameState.world_seed` is overwritten by `SaveSystem.load_or_init()` later, so any computation in `_ready` would use stale seed.
- `compute_placements()` (called by `WorldRoot._ready` after `SaveSystem.load_or_init`):
  1. Find the starter def by id `&"island_meadows_01"`. If missing, `push_error` and `return` (placements stays empty; game runs as a featureless ocean).
  2. Build placement list using `IslandPlacer.place(_defs, GameState.world_seed, WORLD_SIZE_M, 64)`:
     - Slot 0: starter, position `Vector3(0, 0, 0)`, rotation 0.
     - Slots 1..ISLAND_COUNT-1: pick a def at random (weighted by `placement_weight`) using `_rng_for_slot(world_seed, slot_index)`. Pick a candidate position in `[-WORLD_SIZE_M/2, WORLD_SIZE_M/2]^2`. Reject if within `def.footprint_radius + other.footprint_radius + 80` of any already-placed island. Retry up to 64 times. If still rejected, skip slot (`push_warning`).
  3. Each placement gets a stable `runtime_id = StringName("%s::%d" % [def.id, slot_index])`.
  4. Idempotent — calling `compute_placements()` twice with the same seed produces the same list. Overwrites previous list (so a future "new game" UI can call after changing `world_seed`).
- Save-portability: `IslandRegistry` does NOT persist anything. Placements derive entirely from `world_seed`.
- Public API: `placements: Array[IslandPlacement]` (empty until `compute_placements()`), `compute_placements() -> void`, `get_placement_by_runtime_id(runtime_id) -> IslandPlacement`, `get_starter_placement() -> IslandPlacement`.

### WorldStream (== IslandStream)

- Constants: `const LOAD_BUFFER_M := 200.0`, `const UNLOAD_BUFFER_M := 400.0`. Hysteresis: load when ≤ radius+200, unload when > radius+400. The 200 m gap prevents thrash at boundary.
- State: `var player: Node3D`, `var _container: Node3D`, `var _delta_store: IslandDeltaStore`, `var active_islands: Dictionary = {}` (runtime_id → instance).
- `_process(_dt)`:
  1. If `player == null` or `_container == null`, return.
  2. For each placement in `IslandRegistry.placements`:
     - `dist = player.global_position.distance_to(placement.position)`.
     - `load_threshold = placement.def.footprint_radius + LOAD_BUFFER_M`.
     - `unload_threshold = placement.def.footprint_radius + UNLOAD_BUFFER_M`.
     - If `dist <= load_threshold` and `placement.runtime_id not in active_islands`: schedule load (synchronous instantiation is fine — these are pre-baked scenes, no generation cost).
     - If `dist > unload_threshold` and `placement.runtime_id in active_islands`: schedule unload.
  3. After load/unload pass, recompute `player_island` (the placement whose footprint encloses the player, i.e. `dist <= footprint_radius`); if changed, emit `EventBus.biome_entered.emit(<new biome or ocean pseudo-biome>)`.
- `_load_island(placement)`:
  - `instance = placement.def.scene.instantiate()`.
  - `instance.position = placement.position`.
  - `instance.rotation.y = placement.rotation_y`.
  - `_container.add_child(instance)`.
  - Apply deltas: `var deltas = _delta_store.get_deltas_for(placement.runtime_id); _apply_deltas_to_instance(instance, deltas)`.
  - `active_islands[placement.runtime_id] = instance`.
  - `EventBus.island_loaded.emit(placement, instance)`.
- `_unload_island(runtime_id)`:
  - `var inst = active_islands[runtime_id]; inst.queue_free(); active_islands.erase(runtime_id); EventBus.island_unloaded.emit(runtime_id)`.
- **First-batch detection** (for `world_loaded` signal): on first frame after `set_player` and `set_container` are both non-null, do a synchronous load pass that loads all placements within `LOAD_BUFFER_M` of the player. After that pass returns, emit `EventBus.world_loaded` exactly once. Subsequent loads/unloads use the normal `_process` path.

### Ocean pseudo-biome

- The "ocean" biome banner does fire when player leaves an island into open sea. Implement as a special `BiomeDef` instance loaded from `data/biomes/ocean.tres` (or constructed in code if no .tres). `display_name = "The Open Sea"`, `terrain_albedo` unused, ambient tint subtle.
- In `WorldStream._process`'s biome-detection, if no placement encloses the player, emit `biome_entered` with the ocean biome the *first* time the player leaves an island. While in open sea, do not re-emit until a different biome is entered.

### Island delta wiring

- When `ItemPickup` is dropped (e.g. by target_dummy death), the spawn site queries `WorldStream.get_placement_enclosing(drop_pos)`. If non-null:
  1. Compute `local_pos = drop_pos - placement.position` (rotate-inverse if rotation_y ≠ 0; Phase 5 placements use rotation_y = 0 so plain subtraction works — flag this assumption with a comment).
  2. Write delta: `WorldStream.get_delta_store().add_delta(placement.runtime_id, &"dropped_item", {"item_id": ..., "count": ..., "local_position": v3_codec.encode(local_pos)})`.
  3. Parent the live pickup instance to the active island's `DeltaRoot` node so it's visible immediately. Tag it with `_source_runtime_id = placement.runtime_id` + `_source_payload = payload` (same Dictionary reference written to the delta store — survives save/load via `==` content match).
- If `get_placement_enclosing` returns null (open ocean), spawn pickup unparented to scene root with no delta — accepts transience this phase. Won't trigger in Phase 5 (target_dummies sit on starter island), but path must exist.
- On `_load_island`, iterate `&"dropped_item"` deltas, instantiate `ItemPickup.new()`, set `item_id`/`count`/`_source_runtime_id`/`_source_payload`, parent to `instance.get_node("DeltaRoot")`, set `position = v3_codec.decode(payload.local_position)` (local — DeltaRoot is at island origin).
- On pickup, `ItemPickup._on_body_entered` calls `WorldStream.get_delta_store().remove_delta_match(_source_runtime_id, &"dropped_item", _source_payload)` before `queue_free`. Implementation: scan the array, remove first entry whose Dictionary contents `==` match `_source_payload`. Survives save/load (dict contents match across serialisation). **Edge case**: two pickups with identical `{item_id, count, local_position}` collide — first removal eats either one. Acceptable for Phase 5 (placeholder loot drops one scrap at predictable positions).

### Save format

- Existing `SaveSystem.save()` already builds `{header: {version, seed}, payload: {<node.name>: <save_data() result>}}`. New saveables surface as additional payload keys keyed by their `Node.name`. To get reliable keys: name the autoloads as registered (already done — `TimeOfDay`, etc.); name child saveables explicitly via `_island_delta_store.name = "IslandDeltaStore"` before `add_child` (Godot will dedupe with a numeric suffix otherwise — set name explicitly to avoid drift).
- Saveable contract: `save_data() -> Dictionary`, `load_data(d: Dictionary) -> void`. Match the pattern in [skill_manager.gd:58-63](../../mingusbreath/globals/skill_manager.gd).
- Vector3 round-trip: serialise as `[x, y, z]` floats. Helper `scripts/util/v3_codec.gd`: `static encode(v: Vector3) -> Array[float]`, `static decode(a: Array) -> Vector3`.
- Migration: existing `SaveSystem._migrate(payload: Dictionary, from_version: int) -> Dictionary` operates **directly on payload** (already unwrapped from header) and returns the migrated payload. Bump `const SCHEMA_VERSION` from 1 to 2 in [save_system.gd:7](../../mingusbreath/globals/save_system.gd). v1→v2 branch: if `payload.get("IslandDeltaStore")` missing, set `{}`; if `payload.get("TimeOfDay")` missing, set `{game_minutes: 480.0}`; if `payload.get("Player")` missing, leave absent (Player.load_data simply isn't called — fresh-spawn path takes over).
- **Save trigger**: existing flow only triggers `SaveSystem.load_or_init()` from [main.gd:6](../../mingusbreath/scripts/main.gd) and `SaveSystem.save()` from [main.gd:9-11](../../mingusbreath/scripts/main.gd). Test_island.tscn currently bypasses save/load entirely (no call). The new `WorldRoot._ready` MUST call `SaveSystem.load_or_init()`; `WorldRoot._exit_tree` MUST update `GameState.last_played_at` and call `SaveSystem.save()` — copy main.gd verbatim.

### Determinism

- `world_seed` is the only entropy source. Forbidden in the placement and runtime_id paths: `randf()`, `randi()`, `OS.get_unique_id`, `Time.get_ticks_msec`, etc.
- `_rng_for_slot(world_seed, slot_index)`: create a fresh `RandomNumberGenerator`, set `rng.seed = world_seed ^ 0xA1B2C3 ^ slot_index`, optionally `rng.state = 0`. Use only this RNG inside that slot's placement attempt loop.
- Adding a new IslandDef does NOT change existing placements as long as the slot indices and weights are stable. Adding an entry late in the alphabetical scan order can shift weighted picks for later slots. This is acceptable for Phase 5 — document in IslandRegistry header that adding islands may shuffle non-starter placements when world_seed is reused.

### Phase boundaries — what's intentionally NOT in this phase

- Real ocean shader / waves / buoyancy — Phase 8.
- Day/night spawn tables — fields exist on `BiomeDef` but no spawner reads them. Phase 6.
- Foliage scatter — Phase 6.
- Boss anchors — Phase 6+.
- LOD billboards for distant islands — Phase 6 if profiling demands.
- Skybox swap (cubemap per phase) — polish, Phase 7.
- Audio stems per biome — Phase 7.
- New-game UI / seed picker — UI phase.
- Felled-tree / mined-rock delta types — Phase 6.
- Island variants (multiple meadows island shapes) — Phase 6.

---

## Reusable Phase 1–4 Hooks (Don't Re-Invent)

- `SaveSystem.register(self)` + `Saveable` duck-typing — copy the pattern at [game_state.gd:7-18](../../mingusbreath/globals/game_state.gd) for `TimeOfDay`, `IslandDeltaStore`, and the player.
- `EventBus` — every new signal goes here. Match existing declarations in [event_bus.gd](../../mingusbreath/globals/event_bus.gd).
- `IslandGenerator.generate` — used **at edit-time only**, by `bake_islands.gd`. Runtime path is gone.
- `SkillToast` queue — copy verbatim into `BiomeBanner`. Same fade-in/hold/fade-out shape.
- `InventoryRegistry.get_item` — `_apply_deltas_to_instance` uses this when resurrecting `ItemPickup`s from delta payloads.
- `_add_lighting()` from [test_island.gd](../../mingusbreath/scripts/dev/test_island.gd) — port the `DirectionalLight3D` + `WorldEnvironment` setup into `World.tscn` editor-time so the new main scene is lit before TimeOfDay overrides.
- `GameState.world_seed` — single source of truth. Only this seed enters placement.

---

## Verification

End-to-end test before declaring Phase 5 done. Run each step in order; do not skip ahead if a step fails.

1. **Open project.** `Godot_v4.6.2-stable_win64.exe` opens `mingusbreath/project.godot`. Output panel shows zero errors and zero warnings on import. Project Settings → Autoload tab shows 10 entries (added IslandRegistry); Application/Run/Main Scene = `res://scenes/world/World.tscn`.
2. **Bake islands.** Open editor, run `scripts/tools/bake_islands.gd` once. Output panel shows 4 success messages. `assets/islands/` contains 8 `.tres` files (4 mesh + 4 collider). Re-running produces no diff (idempotent).
3. **Cold-start launch.** Delete `user://save.dat`. Press F5.
   - Expected: scene loads in <2 s. Player spawns at the starter island's `SpawnAnchor` position. The starter (Meadows) island is visible underneath.
   - Expected: BiomeBanner shows "Meadows" within ~1 s of spawn.
   - Expected: from a high vantage point (jump? Or temporarily increase camera Y), the other 7 islands are NOT visible — they have not streamed in yet.
4. **Sail/walk to another island.** Use the boat (Phase 3) or walk along the seabed (currently no swim — but the boat works). Approach the nearest other island. As the player gets within `footprint_radius + 200 m`, the island instance pops into the scene tree. Output prints `island_loaded` (add temp print for verification).
5. **Cross into the new island's footprint.** BiomeBanner shows the new biome's `display_name` (e.g. "Forest").
6. **Sail back to starter.** As player exceeds `footprint_radius + 400 m` of the second island, it unloads (`island_unloaded` print). Banner doesn't fire on the unload itself; banner fires on the next biome change (entering Meadows footprint, or first entering open ocean → "The Open Sea").
7. **Determinism check.** Note positions of all 8 islands (open Remote inspector, look at `IslandRegistry.placements`). Quit. Relaunch. Positions match exactly.
8. **TimeOfDay arc.** Set `TimeOfDay.minutes_per_real_second = 60.0` via remote inspector. Watch ~30 s. Expected:
   - Sun visibly rotates.
   - Ambient tint shifts dawn → day → dusk → night.
   - Output shows `time_phase_changed dawn`, `day`, `dusk`, `night` once each per crossing.
   - Reset to 1.0 before continuing.
9. **TimeOfDay save round-trip.** Note `game_minutes`. Quit. Relaunch. `game_minutes` resumes within ~5 minutes drift.
10. **Player position persistence.** Walk far from origin. Note `player.global_position`. Quit. Relaunch. Player at saved pos. Starter island streams in *under* the player (or whichever island encloses — note: if player saved while on a non-starter island, that island must stream first). No fall-through.
11. **Island delta API smoke test.** From a temporary debug action, on starter island, drop a debug ItemPickup. Walk far away (starter unloads). Walk back (starter reloads). Pickup is still there at the recorded local position. Pick it up. Walk far + back. Pickup gone (delta consumed).
12. **Save corruption survives.** Truncate `user://save.dat` to 0 bytes. Relaunch. Game starts with default state, no crash, error logged.
13. **Old test_island regression.** Open `scenes/dev/test_island.tscn` in editor and press F6. Single-island scene still works as in Phase 2/3.
14. **Profiler sanity.** Sail in one direction for 60 s. Average frame ≤ 16 ms. Peak draw calls under 500. Memory growth bounded — load/unload doesn't leak instances.

---

## Out of Scope (Deferred)

Strictly forbidden in this phase:

- Ocean shader / waves / boat buoyancy rewrite — Phase 8.
- Foliage scatter, rocks, trees — Phase 6.
- Day/night spawn tables — Phase 6.
- Multiple enemy types — Phase 6.
- Bosses + boss anchors — Phase 6+.
- Skybox cubemaps swapping per phase — Phase 7.
- Audio stems per biome — Phase 7.
- Map screen — UI phase.
- New-game UI / seed picker — UI phase.
- LOD distant-island impostors — Phase 6 if profiling demands.
- Felled-tree / mined-rock delta types — Phase 6.
- Multiple variants of the same biome (island_meadows_02 etc.) — Phase 6.
- Block + dodge action states (Phase 4 holdover if not yet landed) — finish Phase 4 first.

---

## Critical Files Reference

Files most likely to break or need careful review:

- [globals/world_stream.gd](../../mingusbreath/globals/world_stream.gd) — entire file rewritten as island-streaming.
- [globals/time_of_day.gd](../../mingusbreath/globals/time_of_day.gd) — phase-transition logic must not re-emit on every frame.
- [globals/save_system.gd](../../mingusbreath/globals/save_system.gd) — schema migration v1→v2 must leave existing saves loadable.
- `globals/island_registry.gd` (new) — placement determinism is critical; bugs here break save compat across launches.
- `scripts/world/island_placer.gd` (new) — rejection-sampling correctness; infinite loops if min-distance unsatisfiable.
- `scripts/tools/bake_islands.gd` (new) — editor-time only; must not run during play.
- [scripts/player/player.gd](../../mingusbreath/scripts/player/player.gd) — Saveable + deferred position-set is subtle.
- [globals/event_bus.gd](../../mingusbreath/globals/event_bus.gd) — new signals; listener signatures must match.
- `scripts/world/world_root.gd` (new) — orchestrates startup ordering.
- [project.godot](../../mingusbreath/project.godot) — main_scene change + new IslandRegistry autoload entry.

---

## Execution Order

Each step has a precondition (must be true before starting), an action (what to do), and a verification (how to confirm done before moving on). Do not skip verifications. If a verification fails, fix the cause before proceeding.

### Step 1 — Apply architecture edits to `ARCHITECTURE.md`

- **Precondition.** Clean working tree.
- **Action.** Apply all 6 edits from "Architecture Edits" section above to `mingusbreath/docs/planning/ARCHITECTURE.md`.
- **Verification.** Re-read the modified arch. Each edit appears once. No edit contradicts an earlier section.
- **Commit.** `Phase 5 prep: architecture edits for premade-island streaming + biomes + TimeOfDay`.

### Step 2 — Create `BiomeDef` + 4 biome `.tres` resources

- **Precondition.** Step 1 done.
- **Action.**
  1. Create `mingusbreath/scripts/data/biome_def.gd` with `class_name BiomeDef extends Resource` and the 9 fields per arch edit #1. `@export` every field.
  2. In editor's FileSystem dock, right-click `data/biomes/` → New Resource → `BiomeDef` → save as `meadows.tres`. Set fields.
  3. Repeat for `forest.tres`, `tundra.tres`, `desert.tres`.
  4. Create `data/biomes/ocean.tres` (pseudo-biome for open sea — `id=&"ocean"`, `display_name="The Open Sea"`, `terrain_albedo=Color(0.18, 0.28, 0.42)`, neutral tints).
- **Verification.** All 5 `.tres` files exist; opening each shows correct fields.

### Step 3 — Create `IslandDef` script + bake-islands editor tool

- **Precondition.** Step 2 done.
- **Action.**
  1. Create `mingusbreath/scripts/data/island_def.gd` with `class_name IslandDef extends Resource` and fields per arch edit #2. `@export` every field. `scene` field type is `PackedScene`. `biome` is `BiomeDef`.
  2. Create `mingusbreath/scripts/tools/bake_islands.gd`. **Use `EditorScript` pattern** (one-shot script run from editor Script editor → File → Run). Tree:
     ```gdscript
     @tool
     extends EditorScript
     ## DO NOT run during play. Editor-time only — bakes premade island terrain to .tres.

     func _run() -> void:
         _bake_one(&"island_meadows_01")
         _bake_one(&"island_forest_01")
         _bake_one(&"island_tundra_01")
         _bake_one(&"island_desert_01")

     func _bake_one(def_id: StringName) -> void:
         var seed_ := hash(String(def_id))
         var data := IslandGenerator.generate(seed_, 160, 10.0)
         var mesh_path := "res://assets/islands/%s_mesh.tres" % def_id
         var col_path  := "res://assets/islands/%s_collider.tres" % def_id
         DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/islands/"))
         ResourceSaver.save(data["mesh"], mesh_path)
         ResourceSaver.save(data["collider"], col_path)
         print("baked ", def_id)
     ```
  3. Existing [IslandGenerator.generate](../../mingusbreath/scripts/world/island_generator.gd:5) signature is `(seed: int, size_m: int, max_height_m: float) -> Dictionary` returning `{mesh: ArrayMesh, collider: HeightMapShape3D}`. Plan uses unchanged.
- **Verification.** Editor → Script editor → open `bake_islands.gd` → File → Run. Output panel: `baked island_meadows_01` … 4 lines. `assets/islands/` contains 8 .tres files. Re-running same script reproduces identical files (idempotent — same hash, same noise).
- **Commit.** `Phase 5: BiomeDef + IslandDef schemas + bake-islands tool + 4 starter biomes`.

### Step 4 — Author 4 starter island scenes

- **Precondition.** Step 3 done; baked mesh/collider .tres files on disk.
- **Action.** For each of the 4 islands (meadows, forest, tundra, desert):
  1. In editor, create `scenes/islands/island_<biome>_01.tscn`.
  2. Root: `Node3D` named `Island`.
  3. Add child `MeshInstance3D` named `Terrain`. Set `mesh = preload("res://assets/islands/island_<biome>_01_mesh.tres")`.
  4. On `Terrain`, set `material_override` to a new `StandardMaterial3D`. Set `albedo_color = <biome.terrain_albedo>`. Set `roughness = <biome.terrain_roughness>`.
  5. Add child `StaticBody3D` named `Body`. Add child `CollisionShape3D` of `Body` with `shape = preload("res://assets/islands/island_<biome>_01_collider.tres")`.
  6. Add child `Node3D` named `SpawnAnchor`. Position it ~5 m above the terrain centre (use `Y=8` initially; visually adjust in editor).
  7. Add child `Node3D` named `DeltaRoot` at island origin.
  8. Save scene.
- **Verification.** Open each scene individually with F6. The island terrain renders in its biome colour. SpawnAnchor is visible as a small gizmo on the terrain.

### Step 5 — Create 4 `IslandDef` `.tres` resources

- **Precondition.** Step 4 done.
- **Action.** For each of the 4 islands:
  1. In editor, FileSystem dock → `data/islands/` → New Resource → `IslandDef`.
  2. Save as `island_<biome>_01.tres`.
  3. Set `id = &"island_<biome>_01"`, `display_name`, `scene = preload("res://scenes/islands/<id>.tscn")`, `biome = preload("res://data/biomes/<biome>.tres")`, `footprint_radius` per the table in "Files to Create", `placement_weight = 1.0`.
- **Verification.** Open each `.tres`; all refs resolve, no warnings.
- **Commit.** `Phase 5: 4 starter island scenes + IslandDef resources`.

### Step 6 — Implement `IslandRegistry` autoload + placer

- **Precondition.** Step 5 done.
- **Action.**
  1. Create `globals/island_registry.gd` extending `Node`.
  2. Add to `project.godot` autoloads: `IslandRegistry="*res://globals/island_registry.gd"`. Order: after `WorldStream` (any order works for autoload boot, but registration order = `_ready` order).
  3. **Critical ordering note.** `IslandRegistry._ready` ONLY scans `data/islands/*.tres` into `_defs` — it does NOT compute placements yet. Placement computation depends on `GameState.world_seed`, which is overwritten by `SaveSystem.load_or_init()` AFTER all autoloads have `_ready`'d. Computing at autoload boot would use the default seed (0) and be overwritten silently. Instead expose `compute_placements()` as a public method, called by `WorldRoot._ready` after `SaveSystem.load_or_init()`.
  4. Public API: `_defs: Array[IslandDef]` (filled in `_ready`), `placements: Array[IslandPlacement]` (empty until `compute_placements()` is called), `compute_placements() -> void` (deterministic, idempotent — safe to re-run after seed change), `get_starter_placement() -> IslandPlacement`, `get_placement_by_runtime_id(runtime_id: StringName) -> IslandPlacement`.
  5. Create `scripts/world/island_placer.gd` as a pure-static helper class. Implementation per "Files to Create".
  6. Create `scripts/world/island_runtime_id.gd` pure-static helper.
  7. Define `IslandPlacement` as its own file `scripts/world/island_placement.gd` with `class_name IslandPlacement extends RefCounted` and fields `def: IslandDef`, `position: Vector3`, `rotation_y: float`, `runtime_id: StringName`, `slot_index: int`.
- **Verification.** Temp test: in editor, F5 a throwaway scene that calls `IslandRegistry.compute_placements()` then prints each placement. Quit, relaunch, same positions. Change `GameState.world_seed` (manually edit default in `globals/game_state.gd`), recompute — different positions.
- **Commit.** `Phase 5: IslandRegistry autoload + deterministic placement (deferred compute)`.

### Step 7 — Implement `IslandDeltaStore`

- **Precondition.** Step 6 done.
- **Action.**
  1. Create `scripts/world/island_delta_store.gd`. `class_name IslandDeltaStore extends Node`.
  2. Internal `_deltas: Dictionary` keyed by `runtime_id` (StringName) → `Dictionary` keyed by delta type (StringName) → `Array` of payloads (each payload a `Dictionary`).
  3. Methods: `add_delta(runtime_id: StringName, type: StringName, payload: Dictionary)`, `get_deltas_for(runtime_id) -> Dictionary`, `remove_delta_match(runtime_id, type: StringName, payload: Dictionary)` (walks the array, removes first `==`-matching entry; returns `bool` for found/not-found), `clear_island(runtime_id)`.
  4. Implement Saveable. Godot 4.6 `var_to_bytes` does serialise `StringName`, but to be conservative convert top-level keys to `String` on save and back to `StringName` on load via a `_freeze()`/`_thaw()` pair. `save_data() -> Dictionary` returns `{"deltas": _freeze(_deltas)}`. `load_data(d)` reads `_deltas = _thaw(d.get("deltas", {}))`.
  5. **Set name explicitly before `add_child`**: in WorldStream's `_ready` (Step 8), `var s := IslandDeltaStore.new(); s.name = "IslandDeltaStore"; add_child(s)`. SaveSystem keys payload by `n.name` (see [save_system.gd:18-19](../../mingusbreath/globals/save_system.gd)) — without an explicit name Godot may auto-suffix and drift between runs. Migration in Step 12 also expects exactly `"IslandDeltaStore"`.
  6. `IslandDeltaStore._ready()`: `SaveSystem.register(self)`.
- **Verification.** Temp test: instantiate, set name, add as child of a running scene, call `add_delta` with a known runtime_id, save, restart, load, confirm delta returns.
- **Do not commit yet** — bundle with Step 8.

### Step 8 — Rewrite `WorldStream` for island streaming

- **Precondition.** Step 7 done.
- **Action.**
  1. Open [globals/world_stream.gd](../../mingusbreath/globals/world_stream.gd) (currently a 3-line stub). Add a 1-line top-of-file comment: `## Autoload name kept for back-compat. Internals are island-streaming, not chunk-grid streaming. See Phase 5 plan.`
  2. In `_ready`: instantiate IslandDeltaStore with explicit name (per Step 7.5), add as child, hold ref in `_delta_store`.
  3. Implement `set_player(p: Node3D)`, `set_container(c: Node3D)` setters (gates `_process` until both non-null).
  4. Implement `_process(_dt)` per "Critical Implementation Notes — WorldStream". Iterate `IslandRegistry.placements`, distance-test, load/unload as needed.
  5. Implement `_load_island(placement)` and `_unload_island(runtime_id)`.
  6. Track `_first_batch_done: bool`. On the first frame after both setters are non-null, do a synchronous load pass for all in-range placements. After that pass, `EventBus.world_loaded.emit()` once, then `_first_batch_done = true`.
  7. Implement `get_active_biome() -> BiomeDef`: find nearest enclosing placement (`dist <= footprint_radius`); return its biome, else load and return the ocean BiomeDef from `data/biomes/ocean.tres`.
  8. Track `_last_active_biome: BiomeDef`. Each `_process`, recompute current biome; if different from `_last_active_biome`, emit `EventBus.biome_entered.emit(new_biome)` and update `_last_active_biome`.
  9. **Public accessors** (used by Steps 11 and 14):
     - `get_delta_store() -> IslandDeltaStore`: returns `_delta_store`.
     - `get_placement_enclosing(world_pos: Vector3) -> IslandPlacement`: linear scan over `IslandRegistry.placements`, return first whose `world_pos.distance_to(p.position) <= p.def.footprint_radius`, else null.
     - `active_islands: Dictionary` is read-only-by-convention (Dictionary, not enforced).
- **Verification.** Defer to Step 9 (needs World.tscn).
- **Do not commit yet.**

### Step 9 — Build `World.tscn` + `WorldRoot` + `OceanFollower`

- **Precondition.** Step 8 done.
- **Action.**
  1. Create `scripts/world/ocean_follower.gd` per spec.
  2. Create `scripts/world/world_root.gd`. `_ready()` order is **strict**:
     - **First**: `SaveSystem.load_or_init()`. This populates `GameState.world_seed` from save (or leaves the default for cold start) and fires `load_data` on every Saveable (including Player → stores `_pending_pos`). **Critical**: must run before placement computation. Existing flow only fires from [main.gd:6](../../mingusbreath/scripts/main.gd); test_island.tscn bypasses it. World.tscn must call it explicitly.
     - **Second**: `IslandRegistry.compute_placements()`. Now that `world_seed` is correct, deterministic placement runs.
     - **Third**: wire WorldStream + ocean + sun:
       - `var container = $IslandContainer; var player = $Player`
       - `WorldStream.set_container(container)`
       - `WorldStream.set_player(player)` — triggers first-batch island load + `EventBus.world_loaded.emit` once first batch settles.
       - `$OceanFollower.target = player.get_path()`
       - `TimeOfDay.set_world_environment($WorldEnv.environment)` (TimeOfDay impl in Step 10)
       - `TimeOfDay.set_sun($Sun)`
     - **Fourth**: spawn HUD via script (HUD is `class_name HUD extends CanvasLayer` at [hud.gd:1](../../mingusbreath/scripts/ui/hud.gd) — no `.tscn`): `var hud := HUD.new(); hud.name = "PlayerHUD"; add_child(hud)`. Match [test_island.gd:105-108](../../mingusbreath/scripts/dev/test_island.gd).
  3. Add `WorldRoot._exit_tree()`: `GameState.last_played_at = int(Time.get_unix_time_from_system()); SaveSystem.save()`. Mirror [main.gd:9-11](../../mingusbreath/scripts/main.gd).
  4. Create `scenes/world/World.tscn` matching the tree spec in "Scenes" — but **omit** the HUD child (HUD is spawned by `WorldRoot._ready` since it has no `.tscn`). Lighting: copy DirectionalLight3D + WorldEnvironment settings from `_add_lighting()` at [test_island.gd:55-71](../../mingusbreath/scripts/dev/test_island.gd).
  5. Edit `project.godot` `application/run/main_scene = "res://scenes/world/World.tscn"`.
- **Verification.** Press F5.
   - Player visible in scene; ocean visible underneath; starter island visible at origin.
   - Walk in one direction. Within 200–400 m of another island, it streams in.
   - Sail back across the gap; the second island unloads, starter reloads if it had unloaded.
   - Output prints island_loaded/island_unloaded events (add temp print).
- **Commit.** `Phase 5: WorldStream rewritten for island streaming + World.tscn + ocean follower`.

### Step 10 — Implement `TimeOfDay`

- **Precondition.** Step 9 done.
- **Action.** Per "Critical Implementation Notes — TimeOfDay":
  1. Implement constants, exports (`minutes_per_real_second`, 4 phase-tint colours), `set_world_environment`, `set_sun`.
  2. `_process` ticks `game_minutes`, recomputes phase, on phase change emits `EventBus.time_phase_changed`. Always recompute sun rotation + ambient tint.
  3. Saveable: `save_data` → `{game_minutes}`. `load_data` reads with default 8*60.
  4. Register with SaveSystem in `_ready`.
- **Verification.** F5. Sun visibly rotates. Set `minutes_per_real_second = 60` via remote inspector — sun cycles a day in ~24 real seconds, 4 phase prints fire. Reset to 1.
- **Verification (save).** `game_minutes` ≈ 720 (noon). Quit, relaunch, ≈ 720.
- **Commit.** `Phase 5: TimeOfDay ticking + sun rotation + phase emission + save round-trip`.

### Step 11 — Player position persistence

- **Precondition.** Step 10 done.
- **Action.**
  1. Create `scripts/util/v3_codec.gd` with static `encode(Vector3) -> Array[float]` and `decode(Array) -> Vector3`.
  2. Add `Saveable` to `scripts/player/player.gd`. `save_data` returns `{"position": v3_codec.encode(global_position), "rotation_y": rotation.y}`. **Do not save `hp`/`stamina` this phase** — Phase 4 architecture says they reset on load, and saving fields ignored on load is just noise.
  3. Add member vars: `var _pending_pos = null` (Variant — null sentinel for "no save"), `var _pending_rot_y: float = 0.0`.
  4. `load_data(d)` sets `_pending_pos = v3_codec.decode(d["position"])` and `_pending_rot_y = d["rotation_y"]`. **No connection here** — `_ready` owns the connection.
  5. **In `Player._ready()` (existing function — extend, don't replace)**:
     - `SaveSystem.register(self)` — note Player's node `name` defaults to `"Player"` from the .tscn root; payload key will be `Player` so SaveSystem matches it on load. Children's `_ready` runs before parent's — so by the time `WorldRoot._ready` calls `SaveSystem.load_or_init()`, Player is already registered. (load_data fires DURING that load_or_init, which runs before WorldStream emits world_loaded — so `_pending_pos` is populated before the signal arrives.)
     - `EventBus.world_loaded.connect(_on_world_loaded, CONNECT_ONE_SHOT)` — **always**, both cold-start and returning-user paths. Cold start has `_pending_pos == null`.
  6. `_on_world_loaded()`: if `_pending_pos != null`, set `global_position = _pending_pos; rotation.y = _pending_rot_y`. Else: `var starter := IslandRegistry.get_starter_placement(); var inst := WorldStream.active_islands.get(starter.runtime_id, null); if inst: var anchor := inst.get_node_or_null("SpawnAnchor"); if anchor: global_position = anchor.global_position; else: global_position = Vector3(0, 15, 0)`.
- **Verification.** Walk far. Note pos. Quit. Relaunch. Player at saved pos.
- **Verification (cold-start).** Delete save. Relaunch. Player at starter SpawnAnchor pos.
- **Commit.** `Phase 5: Player position persistence + deferred apply via world_loaded`.

### Step 12 — Save schema migration v1 → v2

- **Precondition.** Step 11 done.
- **Action.**
  1. Open [globals/save_system.gd](../../mingusbreath/globals/save_system.gd). Existing constant is `const SCHEMA_VERSION := 1` at line 7. Bump to `2`.
  2. The existing `_migrate(payload: Dictionary, from_version: int) -> Dictionary` operates on the already-unwrapped payload (header is stripped before _migrate). Add a `from_version == 1` branch:
     ```gdscript
     if from_version == 1:
         if not payload.has("IslandDeltaStore"):
             payload["IslandDeltaStore"] = {}
         if not payload.has("TimeOfDay"):
             payload["TimeOfDay"] = {"game_minutes": 480.0}
         # Player key absent on v1 → load_data simply not called for Player.
     ```
  3. Note: keys match the **registered Saveable's `Node.name`**, not arbitrary strings (`save_system.gd:18-19` uses `payload[n.name] = n.save_data()`). So the migration injects under exactly the names that `IslandDeltaStore.name` and `TimeOfDay` (autoload) carry.
- **Verification.** Hand-craft a v1 save (or use a Phase 4 save). Place at `user://save.dat`. Relaunch. Game loads, no crash, defaults injected. After play+quit, save header bumped to v2.
- **Commit.** `Phase 5: save schema v2 — IslandDeltaStore + TimeOfDay + Player blocks, with v1 migration`.

### Step 13 — Biome banner UI

- **Precondition.** Step 12 done.
- **Action.**
  1. Create `scripts/ui/biome_banner.gd` as `class_name BiomeBanner extends CanvasLayer`. **No `.tscn`** — match the script-only convention used by [hud.gd](../../mingusbreath/scripts/ui/hud.gd) and [skill_toast.gd](../../mingusbreath/scripts/ui/skill_toast.gd). Layer 8 (between SkillToast at 10 and HUD at 9). In `_ready`, build the Label programmatically (centered, anchor 0.5, font size ~32, default `modulate.a = 0.0`).
  2. Listen to `EventBus.biome_entered`. Copy the queue pattern from [skill_toast.gd:5-7,32-47](../../mingusbreath/scripts/ui/skill_toast.gd) verbatim — `_queue: Array[String]`, `_busy: bool`, recursive `_show_next` via `tween_callback`. Adjust timings: tween 0.3s → interval 1.4s → tween 0.3s.
  3. Spawn from `HUD._ready()` — extend [hud.gd](../../mingusbreath/scripts/ui/hud.gd) to `add_child(BiomeBanner.new())` after the SkillToast instantiation. Same pattern.
- **Verification.** Sail from starter to another island. Banner shows starter biome on spawn, then briefly "The Open Sea" when leaving footprint, then the new island's biome. Cross rapidly back and forth — queue handles correctly.
- **Commit.** `Phase 5: BiomeBanner UI + biome_entered wiring`.

### Step 14 — Wire island delta apply for dropped items

- **Precondition.** Step 13 done.
- **Action.**
  1. **ItemPickup is script-only** (no `.tscn` — confirmed at [item_pickup.gd](../../mingusbreath/scripts/items/item_pickup.gd) — instantiated via `ItemPickup.new()`). Spawn pattern: `var p := ItemPickup.new(); p.item_id = ...; p.count = ...; parent.add_child(p); p.global_position = ...`.
  2. In `WorldStream._load_island`, after parenting the island instance, fetch `var deltas := _delta_store.get_deltas_for(placement.runtime_id)`. For each `&"dropped_item"` payload (a `Dictionary` with keys `item_id`, `count`, `local_position`): create `ItemPickup.new()`, set `item_id` + `count`, parent to `instance.get_node("DeltaRoot")` (a `Node3D` child added in Step 4), set `position = v3_codec.decode(payload["local_position"])`. Tag pickup: `pickup._source_runtime_id = placement.runtime_id; pickup._source_payload = payload`.
  3. Extend [item_pickup.gd](../../mingusbreath/scripts/items/item_pickup.gd) with two new vars: `var _source_runtime_id: StringName = &""` and `var _source_payload: Dictionary = {}`. In `_on_body_entered`, after `body.take_pickup(item_id, count)` and **before** `queue_free()`, add:
     ```gdscript
     if _source_runtime_id != &"":
         WorldStream.get_delta_store().remove_delta_match(_source_runtime_id, &"dropped_item", _source_payload)
     ```
  4. Existing target_dummy death-drop site (Phase 3) currently spawns an `ItemPickup` — read [target_dummy.gd](../../mingusbreath/scripts/ai/target_dummy.gd) (located in `scripts/ai/`) and modify so on death:
     - `var placement := WorldStream.get_placement_enclosing(global_position)` (helper added in Step 8).
     - If non-null: build `var local_pos := global_position - placement.position`. Build `var payload := {"item_id": &"scrap", "count": 1, "local_position": v3_codec.encode(local_pos)}`. Call `WorldStream.get_delta_store().add_delta(placement.runtime_id, &"dropped_item", payload)`. Instantiate live pickup, parent to `WorldStream.active_islands[placement.runtime_id].get_node("DeltaRoot")`, set local position, tag with `_source_runtime_id` + `_source_payload`.
     - If null: spawn unparented (current behaviour preserved); won't fire in Phase 5.
- **Verification.** Use a debug action to drop a test pickup on the starter island. Sail far enough to unload starter (≥ footprint+400m). Sail back (starter reloads). Pickup is at the same local position. Pick it up. Sail far + back. Pickup gone (delta consumed).
- **Commit.** `Phase 5: island delta apply for dropped items, with consume-on-pickup`.

### Step 15 — Full verification pass

- **Precondition.** Steps 1–14 done, all per-step verifications passed.
- **Action.** Run the 14-step "Verification" list from the section above, top to bottom.
- **Commit.** No commit. Integration test only.

### Step 16 — Final cleanup commit

- **Precondition.** Step 15 fully passes.
- **Action.**
  1. Remove or comment temp `print()` debug statements.
  2. Verify `application/run/main_scene = res://scenes/world/World.tscn`.
  3. Update `mingusbreath/README.md` "Systems" table: change Phase 5 row to "Phase 5 — done" and link this doc.
- **Commit.** `Phase 5: README + cleanup; phase complete`.

---

## Plan-Revision Note

Original Phase 5 plan shipped chunk-grid streaming (128 m chunks, sea-threshold continent noise, per-chunk biome assignment via Perlin). User feedback: drop the Valheim-style fully-procedural islands; want premade islands at random positions on a big ocean.

Dropped:
- Chunk grid + per-chunk Mesh streaming.
- Continent-noise island shape decisions.
- Per-chunk biome assignment (`BiomeAssigner`).
- `Chunk.tscn` / `chunk.gd` / `chunk_keys.gd` / `chunk_delta_store.gd`.
- WorkerThreadPool async chunk gen.
- Seam-vertex matching verification (no seams now — islands are isolated meshes).

Kept:
- Ocean follower pattern (single big plane following player XZ).
- TimeOfDay + sun rotation + phase emission + save.
- Biome banner UI + queue.
- Save schema v1→v2 migration shape.
- Player-position persistence with deferred apply via `world_loaded`.

Added:
- Premade island scenes (4 starter, baked from generator at edit-time, hand-editable thereafter).
- `IslandDef` resource + `IslandRegistry` autoload + `island_placer.gd` (rejection sampling).
- Island-distance streaming with hysteresis.
- Per-island delta store keyed by stable runtime_id.

Net effect: simpler runtime, less threading risk, more authorial control, identical-feeling streamed-multi-island world.

---

## Notes for the implementing model

- This plan assumes Phase 4's HP/stamina/block/dodge/husk work is **either complete or formally deferred**. If Phase 4 is still outstanding, finish it first.
- All placement parameters (WORLD_SIZE_M, ISLAND_COUNT, footprint_radius defaults, LOAD_BUFFER_M, UNLOAD_BUFFER_M) are tunable. Initial values in this doc are starting points — adjust during Step 15 verification by feel and document with `// TUNED:` comments.
- The single biggest risk is `IslandRegistry` placement determinism. Step 6 verification (positions match across two launches) is non-negotiable.
- Save schema migration is the second-biggest risk. Step 12 needs a real v1 save round-trip — do not skip.
- If `min_distance` rejection-sampling can't seat all 8 islands within `WORLD_SIZE_M = 4096` and the configured footprints, prefer to *grow `WORLD_SIZE_M`* (e.g. to 6144) over silently dropping islands. Document the tweak.
- Caveman style applies to chat replies, not this plan file. Plan file matches existing PHASE_*_PLAN.md voice.
