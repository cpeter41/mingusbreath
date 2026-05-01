# Phase 1 Plan — Architecture Review + Project Skeleton

## Context

`mingusbreath/` currently contains only [ARCHITECTURE.md](ARCHITECTURE.md) and a `.git` folder. The doc describes a Godot 4.6 single-player open-world game; this phase (a) tightens a few architectural inconsistencies and (b) executes the doc's own "Phase 1" — project skeleton + all autoload stubs + a save round-trip — so every later vertical slice has a stable harness to plug into.

The goal is a project that opens cleanly in the editor, F5-runs into a placeholder scene, has all ten global services registered and importable, and can save/restore a single dummy value across a relaunch. Nothing more — gameplay slices begin in Phase 2.

---

## Architecture Edits (to be applied to `ARCHITECTURE.md`)

Small but worth fixing before any code lands, because they affect file paths and class names that downstream phases will hard-code:

1. **`WorldStream` location is contradictory.** Line 64 lists it as an autoload (which by convention should live in `globals/`), but line 94 says `scripts/world/world_stream.gd`, and line 263 puts it in `globals/`. **Fix:** move the autoload to `globals/world_stream.gd` (matches the other 9 autoloads); keep non-autoload helpers (`chunk.gd`, `island_generator.gd`, `foliage_scatter.gd`) under `scripts/world/`.
2. **Terrain mesh vs collider clarification.** Line 87 reads as if `ArrayMesh` and `HeightMapShape3D` are alternatives, but they're complementary — `ArrayMesh` is the visual mesh, `HeightMapShape3D` (or a trimesh from the same heights) is the collider. Reword to make that explicit.
3. **Implementation Order step 1 understates Phase 1.** It lists "EventBus + SaveSystem" as the first slice, but to avoid churning `project.godot` later it's much cheaper to register all ten autoload stubs at once. Reword step 1 to: "Project skeleton + all ten autoload stubs registered + EventBus signals enumerated + SaveSystem round-tripping one dummy field."
4. **Add an InputMap section.** Combat/movement/sail will all need named input actions — defining the canonical action names early avoids a later rename pass. Canonical actions:
   - Movement: `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `dodge`
   - Combat: `attack_light`, `attack_heavy`, `block`, `interact`
   - UI: `inventory`, `map`, `pause`
   - Boat mode: `throttle_up`, `throttle_down`, `rudder_left`, `rudder_right`, `fire_cannon`
5. **Pin the world-unit convention.** Architecture talks about "128 m chunks" — add one sentence stating "1 Godot unit = 1 meter" so meshes/scales aren't ambiguous.

---

## Phase 1 Deliverables

A runnable Godot 4.6 project with:

- `project.godot` configured for Forward+ renderer, 1 m units, the InputMap from edit #4 above, all ten autoloads registered. **Hand-written as INI** — no editor round-trip required to bootstrap.
- The directory tree from the architecture's "Project Layout" section, scaffolded with `.gdkeep` files where empty.
- All ten autoloads as minimal `Node` scripts with their public API stubbed (signals declared, methods returning safe defaults).
- A root `scenes/main.tscn` that loads on play and shows a "Mingusbreath — skeleton OK | last_played: <timestamp>" label, plus a `DirectionalLight3D` and `WorldEnvironment` so the scene isn't black.
- `SaveSystem` with real atomic-write logic (write `save.tmp`, flush, rename over `save.dat`), a version-tagged header (`{version: 1, seed: 0}`), and one dummy persisted field (`GameState.last_played_at`) that round-trips across a relaunch.
- `EventBus` with all signals from line 61 of ARCHITECTURE.md declared (no listeners yet).
- A `Saveable` interface convention documented as a one-liner comment in `save_system.gd` (`save_data() -> Dictionary`, `load_data(d: Dictionary) -> void`).

No `Logger` autoload yet — `print` / `push_error` / `push_warning` are sufficient until structured logging is justified.

---

## Files to Create

### Autoloads (each is a thin stub — signals + empty methods)

- `globals/event_bus.gd` — declares all project-wide signals.
- `globals/game_state.gd` — `world_seed: int`, `paused: bool`, `last_played_at: int`. Implements `Saveable`.
- `globals/save_system.gd` — full atomic save/load, version header, registry of saveables.
- `globals/time_of_day.gd` — clock var + `phase` enum, `_process` no-op for now.
- `globals/world_stream.gd` — empty stub (no streaming yet).
- `globals/skill_manager.gd` — `{skill_id: {level, xp}}` dict, `add_xp` no-op.
- `globals/inventory_registry.gd` — `_ready` scans `data/items/` (currently empty, that's fine).
- `globals/discovery_log.gd` — sets for regions + stations; Saveable.
- `globals/audio_director.gd` — empty stub.

### Project / scene files

- `project.godot` — autoloads registered, InputMap populated, Forward+ renderer, app name "Mingusbreath".
- `scenes/main.tscn` + `scripts/main.gd` — placeholder root scene that on `_ready` calls `SaveSystem.load_or_init()` and updates the label with the loaded `last_played_at`; on `_exit_tree` writes the current timestamp back via `SaveSystem.save()`.
- `.gitignore` — Godot-standard (`.godot/`, `*.translation`, `export.cfg`, etc.).
- `.gdkeep` markers in every empty directory from the layout in ARCHITECTURE.md so the structure survives git.

---

## Critical Implementation Notes

- **Atomic save:** `FileAccess.open(temp, WRITE)` → `store_var({header, payload})` → `flush()` → close → `DirAccess.rename(temp, final)`. Wrap in error checks; on any failure, leave the existing `save.dat` untouched.
- **Saveable registry:** `SaveSystem` keeps a `_saveables: Array[Node]`; autoloads call `SaveSystem.register(self)` from `_ready`. `save()` iterates registered nodes; `load()` distributes data by node name. Keeps autoloads decoupled from save-system internals.
- **Schema version:** header is `{"version": 1, "seed": 0}`. Add a `_migrate(data, from_version)` method that's a no-op at v1 — its existence proves the migration hook is wired.
- **No gameplay logic in any autoload yet** — every autoload exists to prove it loads and (where relevant) round-trips its `Saveable` contract.

---

## Verification

End-to-end test before declaring Phase 1 done:

1. Open `mingusbreath/project.godot` in `Godot_v4.6.2-stable_win64.exe`. No import errors in the Output panel.
2. Project Settings → Autoload tab shows all 10 entries, all enabled.
3. Project Settings → Input Map shows the canonical actions from edit #4.
4. Press F5 → main.tscn opens, label reads `Mingusbreath — skeleton OK | last_played: 0` on first run.
5. Quit. A `save.dat` file exists in `user://`.
6. Relaunch and press F5 — label now reads the saved timestamp from the previous session.
7. Manually corrupt `save.dat` (truncate to 0 bytes) → relaunch → game starts with defaults, no crash, error logged to Output panel.
8. Open the Profiler — idle frame budget effectively free (autoloads do nothing yet).

---

## Out of Scope for Phase 1

Deferred to later phases per ARCHITECTURE.md §"Implementation Order":

- Player controller, camera, any movement.
- World streaming, chunks, terrain, ocean.
- Combat, skills, inventory, crafting.
- Boats, AI, time-of-day visuals, UI screens.
- GUT test setup (defer until SaveSystem grows enough state to be worth testing).

---

## Execution Order

1. Apply the five edits to `ARCHITECTURE.md`.
2. Write `project.godot` + `.gitignore` + directory scaffolding (`.gdkeep` files).
3. Write all 10 autoload stubs.
4. Write `scenes/main.tscn` + `scripts/main.gd`.
5. Wire `SaveSystem` round-trip with `GameState.last_played_at`.
6. Run the 8-step verification above; iterate on any failures.
7. One git commit at the end: "Phase 1: project skeleton + autoloads + save round-trip".
