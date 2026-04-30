# Phase 2 Plan — Playable Character + Combat Stub + Test Island

## Context

Phase 1 shipped the project skeleton: 9 autoloads, InputMap, atomic save round-trip, placeholder [main.tscn](scenes/main.tscn). Nothing is playable yet — pressing F5 shows a label on a blank background.

Phase 2 turns the skeleton into a first **playable vertical slice**:
- A controllable third-person character that walks, sprints, jumps, and falls with gravity.
- A swing-on-click melee attack with a real hitbox/hurtbox damage flow.
- A stationary target dummy that takes damage, shows a hit reaction, and despawns at 0 HP.
- A small procedurally-generated heightmap test island to stand on (proves `island_generator.gd` early without committing to streaming).
- Minimal Run/Jump/Swords XP accumulation (no level-up curve yet).

This combines arch [Implementation Order](ARCHITECTURE.md) step 2 (player+camera), a sliver of step 4 (one heightmap island), and a stripped step 5 (hitbox/hurtbox + dummy target). World streaming, biomes, AI, inventory, crafting, and full skill curves stay out.

---

## Deliverables

A Godot 4.6 build where, on F5:

1. Player spawns on a small (~120 m × 120 m) heightmap island over a flat blue water plane (no shader yet — placeholder `MeshInstance3D` plane).
2. WASD walks; Shift sprints; Space jumps; gravity pulls down off ledges. Mouse turns the third-person camera; camera collides with terrain via `SpringArm3D`.
3. Left-click swings the equipped sword (animation track or simple `Tween` rotation). During the active window, the sword's `Area3D` hitbox damages overlapping `Hurtbox`es.
4. A target dummy stands on the island. Hits flash it red, drop its HP, and at 0 HP it queue-frees and emits `EventBus.enemy_killed`.
5. Run/Jump time and successful sword hits accumulate XP in `SkillManager.skills` (visible by printing on level-up if implemented later, or by inspecting in-debugger).
6. `Esc` releases mouse capture so dev iteration is sane.

Save round-trip from Phase 1 still works (player position is **not** persisted yet — deferred to phase that owns Saveable expansion).

---

## Architecture Edits (apply to `ARCHITECTURE.md` before code lands)

1. **State machine scope**: arch lists 11 player states (Idle, Run, Sprint, Jump, Fall, Swim, Block, Attack, Dodge, Sail). Phase 2 implements only Idle/Run/Sprint/Jump/Fall/Attack. Add a one-liner under §"Player & Combat" noting that phases ship subsets and the dir `scripts/player/states/` is grown incrementally.
2. **CombatResolver minimal contract**: arch describes `CombatResolver` but doesn't pin its signature. Pin it: `static resolve(attacker: Node, target: Node, weapon_id: StringName, base_damage: float) -> float` returning final damage after skill multipliers and resistances. Phase 2 implementation just returns `base_damage` (multipliers come with full skill system).
3. **Test scene convention**: add a `scenes/dev/` directory for throwaway sandboxes. Phase 2's island test bed lives there (`scenes/dev/test_island.tscn`); `main.tscn` redirects there until a real spawn flow exists.

---

## Files to Create

### Player
- `scripts/player/player.gd` — `CharacterBody3D`, holds HP/Stamina vars, owns state machine, applies velocity per active state.
- `scripts/player/player_camera.gd` — third-person `SpringArm3D` rig; mouse-relative yaw (on player body) + pitch (on spring arm); clamps pitch.
- `scripts/player/states/state.gd` — base class: `enter()`, `exit()`, `physics_update(delta)`, `handle_input(event)`, `transition_to(name)`.
- `scripts/player/states/idle.gd`, `run.gd`, `sprint.gd`, `jump.gd`, `fall.gd`, `attack.gd` — minimal implementations.
- `scripts/player/state_machine.gd` — owns the active state node, dispatches `_physics_process` / `_input` to it.
- `scenes/player/Player.tscn` — `CharacterBody3D` root; child `CapsuleShape3D` collision; `MeshInstance3D` (capsule primitive, toon material later); `Node3D` `CameraPivot` → `SpringArm3D` → `Camera3D`; `Node3D` `WeaponMount` w/ a child `Sword` scene.

### Combat
- `scripts/combat/hitbox.gd` — `Area3D` script; exports `damage`, `weapon_id`, `skill_id`; toggled active on signal from anim/attack state.
- `scripts/combat/hurtbox.gd` — `Area3D` script; on `area_entered` w/ a Hitbox, calls `CombatResolver.resolve(...)`, applies damage to its owner's `take_damage(amount)` method (duck-typed).
- `scripts/combat/combat_resolver.gd` — `class_name CombatResolver`; static `resolve()` per edit #2. Emits `EventBus.damage_dealt`.
- `scenes/weapons/Sword.tscn` + `scripts/combat/sword.gd` — mesh + Area3D Hitbox; `swing()` enables hitbox for ~0.2 s, plays a `Tween` rotation.

### Enemy (target dummy)
- `scripts/ai/target_dummy.gd` — `StaticBody3D` w/ HP int; `take_damage(amount)`; flashes a `MeshInstance3D` red via material override; queue_free + `EventBus.enemy_killed.emit(...)` on death.
- `scenes/ai/TargetDummy.tscn` — root StaticBody3D, mesh, collision, `Hurtbox` Area3D child.

### World (test island)
- `scripts/world/island_generator.gd` — pure function `generate(seed: int, size_m: int, max_height_m: float) -> {mesh: ArrayMesh, collider: HeightMapShape3D}`. Uses `FastNoiseLite` (continent + detail layered). Reused later by streaming.
- `scenes/dev/test_island.tscn` + `scripts/dev/test_island.gd` — `_ready` calls `island_generator.generate(GameState.world_seed, 120, 8.0)`, builds `MeshInstance3D` + `StaticBody3D` w/ `CollisionShape3D` (HeightMapShape3D), spawns Player and ~3 TargetDummys at preset offsets, plus a flat `MeshInstance3D` water-plane placeholder under the island.

### Skills
- `globals/skill_manager.gd` — replace stub `add_xp` with: `skills[id] = {level: 1, xp: 0.0}` if missing; increment xp; emit `EventBus.skill_xp_gained`. **No** level-up math yet (deferred). Implement `Saveable` so XP persists.

### Wiring
- `scripts/player/states/run.gd` & `sprint.gd` — accumulate Run XP per second active.
- `scripts/player/states/jump.gd` — add 1 Jump XP on `enter()`.
- `scripts/combat/combat_resolver.gd` — on hit landed, `SkillManager.add_xp(skill_id, base_damage * 0.1)`.

### Project changes
- `project.godot` — set `application/run/main_scene = "res://scenes/dev/test_island.tscn"` for phase 2. Revert when real spawn flow lands.
- `scenes/main.tscn` — leave as-is (still useful as save round-trip smoke test); reachable via debug menu later.

---

## Critical Implementation Notes

- **Mouse capture**: `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)` on `_ready`; `Esc` toggles to `MOUSE_MODE_VISIBLE`. Pause action will subsume this later.
- **Gravity**: read from `ProjectSettings.get_setting("physics/3d/default_gravity")` (default 9.8). Don't hard-code.
- **Hitbox active window**: gate via a bool the attack state flips on at frame `attack_start_offset` and off at `attack_end_offset` — 0.05 s and 0.25 s into the swing for now. No anim file required; a `Tween` on weapon rotation is enough this phase.
- **Hurtbox/Hitbox layers**: dedicate physics layer 2 to "hitbox" and layer 3 to "hurtbox"; hitbox's `collision_mask` only includes layer 3 and vice versa. Avoids Area3D self-overlap noise.
- **Damage signal payload**: `EventBus.damage_dealt(attacker, target, weapon_id, skill_id, amount)` already exists — reuse, don't add new signals.
- **Determinism**: `island_generator.generate()` must be a pure function of `(seed, size, max_height)`. No `randf()`. Use `FastNoiseLite.seed = seed`. Required so the streaming phase can reuse it without rework.
- **No persistence of player/enemy state this phase** — explicitly out of scope. Phase that adds enemies-as-real-NPCs owns that.

---

## Reusable Phase 1 Hooks (Don't Re-Invent)

- `EventBus` signals `damage_dealt`, `enemy_killed`, `skill_xp_gained` — already declared in [event_bus.gd](globals/event_bus.gd:11). Emit, don't add new ones.
- `SaveSystem.register(self)` pattern — when SkillManager becomes Saveable, copy [game_state.gd](globals/game_state.gd:7-18) verbatim.
- `GameState.world_seed` — feed into `island_generator.generate()` so reload re-creates the same island.

---

## Verification

1. Open `mingusbreath/project.godot` in `Godot_v4.6.2-stable_win64.exe`. No import errors.
2. Press F5 → camera renders a hilly green island over a blue plane; player capsule stands on it.
3. WASD moves, capsule slides along terrain, falls off ledges with gravity. Shift accelerates. Space jumps once per ground contact.
4. Mouse rotates camera; pitch clamped, no flip-over.
5. Three target dummies visible on island. Walk up, left-click — sword swings, dummy flashes red, takes damage, despawns after enough hits.
6. Output panel shows `damage_dealt` and `enemy_killed` prints from temp debug listeners on `EventBus`.
7. Inspect `SkillManager.skills` in remote debugger after ~30 s play: entries for `&"run"`, `&"jump"`, `&"swords"` exist with non-zero `xp`.
8. Quit, relaunch — `save.dat` round-trip from phase 1 still passes (label scene reachable via direct `main.tscn` open verifies). Skill XP persists if SkillManager Saveable wired.
9. `Esc` releases mouse; click the window restores capture (or pressing a movement key).

---

## Out of Scope (Deferred)

- Block, dodge, ranged/bow, stamina drain — phases owning combat depth.
- Real enemy AI (sense → chase → attack), spawners, biome tables — arch step 5/AI phase.
- Chunk streaming, multi-island world, ocean shader — arch step 3/4/8.
- Inventory, equipment swap, weapon variety — arch step 7.
- Skill level-up curves, `SkillDef` resources, HUD toasts — arch step 6.
- Player HP/death UX, respawn — later.
- Animations beyond `Tween` placeholders, model art — later.
- Persisting player position / enemy state — owned by the phase that turns enemies into real NPCs.

---

## Execution Order

1. Apply 3 architecture edits to `ARCHITECTURE.md`.
2. `island_generator.gd` + `test_island.tscn` standalone — verify F5 shows terrain w/ collider.
3. `Player.tscn` + `player.gd` + camera, no states yet — verify capsule moves and camera follows.
4. State machine scaffold + Idle/Run/Sprint/Jump/Fall — verify all transitions in dev.
5. `Sword.tscn` + Hitbox/Hurtbox/CombatResolver — verify hit detection prints `damage_dealt`.
6. `TargetDummy.tscn` — verify HP drain + death.
7. SkillManager XP accumulation + Saveable — verify dict populates.
8. Run 9-step verification; iterate.
9. Commit: "Phase 2: playable character + melee + target dummy + test island".
