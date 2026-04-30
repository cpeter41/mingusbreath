# Phase 3 Plan — Skill Curves + Inventory v0 + Basic Boat

## Context

Phase 2 shipped a playable slice: character controller (split `movementSM` + `actionSM` — keep, already documented), sword swing w/ Hitbox/Hurtbox/CombatResolver, target dummy w/ HP, procedural test island, raw XP accumulation in `SkillManager`. XP goes up but nothing happens — no level-ups, no rewards, no items. Test island sits over a flat blue water-plane placeholder w/ nothing to do on it.

Phase 3 closes a small progression loop: **kill dummy → level skill → see toast → loot drop → pick up → see in inventory**. Plus a stripped-down **rideable boat** so the water plane stops being decorative — board, drive, dismount. No crafting (deferred), no new combat, no buoyancy sim, no waves.

This is arch [Implementation Order](ARCHITECTURE.md) step 6 (skill curves) + part of step 7 (inventory only — crafting deferred) + a sliver of step 8 (boat — minimal). Streaming, biomes, real enemy AI, ranged combat, naval combat, ocean shader, time-of-day, crafting stations all out.

**Boat scope deviation note:** arch §"Boats & Naval Combat" describes `RigidBody3D` w/ buoyancy script sampling water-height. Phase 3 ships a `CharacterBody3D` pinned to fixed water Y (the placeholder plane has no waves). When the real ocean shader lands (Phase 8), boat will be rewritten to `RigidBody3D` + buoyancy. Keep boat code in `scripts/ships/` so the rewrite is local.

---

## Deliverables

After F5 on the existing test island:

1. Hitting target dummy ticks Swords XP. At threshold, `EventBus.skill_leveled` fires; HUD shows a toast ("Swords reached level 2"); brief audio sting (placeholder beep ok).
2. Dummy at 0 HP drops a small "scrap" loot item — visible mesh on ground w/ a pickup `Area3D`.
3. Walking onto loot picks it up, plays a sfx, fires `EventBus.item_picked_up`, shows a brief HUD line ("+1 scrap").
4. Player has an inventory (cap 20 slots, stack of 99). `I` opens an inventory screen — grid of slots, hover tooltip from `ItemDef`. `Esc` or `I` closes.
5. **Boat:** a small boat sits in water near the island. Press `interact` near it → camera switches to boat, player capsule hides, `Sail` action state activates. `throttle_up/down` accelerates/reverses, `rudder_left/right` turns, boat glides on water at fixed Y. `interact` again → dismount, player teleports to a deck-side spawn point, boat decelerates to stop. Land collision blocks boat (can't ram through island).
6. Save round-trip: skill levels and inventory contents persist across relaunch. Boat position **not** persisted this phase (deferred to persistence pass alongside the RigidBody3D rewrite).

HUD remains minimal — no HP/stamina bars yet. Inventory + toast are the only screens.

---

## Architecture Edits (apply to `ARCHITECTURE.md` first)

1. **Pin SkillDef shape.** Arch §"Skill System" mentions `SkillDef` resources but doesn't pin fields. Add: `id: StringName, display_name: String, xp_curve: PackedFloat32Array (cumulative XP-to-next thresholds), per_level_damage_mult: float = 1.0, per_level_stamina_mult: float = 1.0`. Phase 3 only uses `id`, `display_name`, `xp_curve` — multipliers are fields-not-yet-applied, reserving the slot.
2. **Pin ItemDef shape.** Arch references `ItemDef` but no schema. Add: `id: StringName, display_name: String, description: String, icon: Texture2D, max_stack: int = 99, item_type: enum { GENERIC, MATERIAL, WEAPON, TOOL, CONSUMABLE }, weapon_skill_id: StringName = &""` (for weapons).
3. **Document SM split.** Arch §"Player & Combat" still describes a single state machine. Add a sentence: `Phase 2 split this into two parallel state machines — movementSM (locomotion) and actionSM (attack/block/dodge) — running independently. Kept because it cleanly separates concerns.`
4. **Note inventory persistence pattern.** Arch §"Save System" lists inventory as persisted. Add: `Inventory persists as a flat array of {item_id, count} stacks; ItemDef refs are resolved on load via InventoryRegistry, never serialized.`
5. **Boat phasing note.** Arch §"Boats & Naval Combat" assumes `RigidBody3D` + buoyancy from day one. Add: `Phase 3 ships a stub CharacterBody3D boat pinned to a flat water plane — no buoyancy, no waves, no naval combat. Rewritten to RigidBody3D + buoyancy in Phase 8 when the ocean shader lands.`
6. **Add Sail to player action states.** Arch §"Player & Combat" lists Sail as a state. Phase 3 implements a minimal Sail: blocks all other action input, drives boat instead of player. Player capsule hidden during Sail. Movement SM frozen (Idle).

(`RecipeDef` schema deferred — pin when crafting phase lands.)

---

## Files to Create

### Data resources (definitions)

- `scripts/data/skill_def.gd` — `class_name SkillDef extends Resource`, fields per edit #1.
- `scripts/data/item_def.gd` — `class_name ItemDef extends Resource`, fields per edit #2.

### Data instances (.tres)

- `data/skills/swords.tres` — xp curve `[10, 30, 80, 200, 500]` (placeholder, tune later).
- `data/skills/run.tres`, `data/skills/jump.tres` — same curve shape.
- `data/items/scrap.tres` — MATERIAL.
- `data/items/sword.tres` — for the player's existing sword (reference, not yet wielded from inventory).

### Scripts

- `scripts/inventory/inventory.gd` — `class_name Inventory extends Node`. API: `add(item_id, count) -> int (overflow)`, `remove(item_id, count) -> bool`, `count_of(item_id) -> int`, `slots: Array[Dictionary]`. Implements Saveable.
- `scripts/items/item_pickup.gd` — `class_name ItemPickup extends Area3D`. Exports `item_id: StringName`, `count: int`. On body_entered (player), calls `Player.inventory.add(...)`, fires `EventBus.item_picked_up`, queue_frees. Spawns w/ a small `MeshInstance3D` placeholder (cube, color from item_type).
- `scripts/ui/skill_toast.gd` + `scenes/ui/SkillToast.tscn` — `CanvasLayer` w/ a `Label` that fades in/out on `EventBus.skill_leveled`. Pooled or a queue of pending toasts.
- `scripts/ui/inventory_screen.gd` + `scenes/ui/InventoryScreen.tscn` — `CanvasLayer` w/ `GridContainer` of slot widgets. Toggled by `inventory` input action. Pauses world (`get_tree().paused = true`) while open.
- `scripts/ui/hud.gd` + `scenes/ui/HUD.tscn` — thin root; hosts the toast layer + a transient pickup line. Mounted in test_island.tscn.

### Boat

- `scripts/ships/boat.gd` — `class_name Boat extends CharacterBody3D`. Vars: `throttle: float` (-1..+1), `max_speed: float = 12.0`, `accel: float = 4.0`, `turn_rate_deg: float = 45.0`, `water_y: float = 0.0` (set by test_island on instance). State: `mounted: bool`. `_physics_process` reads inputs *only when mounted*, integrates velocity, pins `position.y = water_y`, applies turn around Y axis, calls `move_and_slide` so land collider stops it.
- `scripts/ships/boat_camera.gd` — `SpringArm3D` rig parented to boat root. Mouse controls yaw offset + pitch (clamped). Activated on mount, deactivated on dismount.
- `scripts/ships/boat_mount.gd` — small `Area3D` child of boat. Tracks player overlap. On `interact` press while overlapping + not mounted, calls `Boat.mount(player)`. While mounted, `interact` calls `Boat.dismount()`.
- `scenes/ships/Boat.tscn` — `CharacterBody3D` root; child `MeshInstance3D` (placeholder elongated box, brown material); `CollisionShape3D` (BoxShape3D matching hull); `Node3D` `DeckSpawn` (offset for player teleport on dismount); `Node3D` `CameraPivot` → `SpringArm3D` → `Camera3D`; `Area3D` mount zone.

### Player action state

- `scripts/player/action_states/sail.gd` — empty enter/exit hooks; toggles player capsule visibility, disables hitbox processing, hands camera control to boat. On exit, restore.

### Modifications to existing files

- `globals/skill_manager.gd` — extend `add_xp`: after incrementing xp, look up `SkillDef` from a new `_defs` dict (loaded in `_ready` from `data/skills/*.tres`); compute new level by walking `xp_curve`; if level changed, set `skills[id].level` and emit `EventBus.skill_leveled(id, new_level)`. Backward-compatible w/ existing save dict shape.
- `globals/inventory_registry.gd` — already scans `data/items/`. Add `get_all() -> Array[ItemDef]` for UI. No structural change needed.
- `scripts/player/player.gd` — add `var inventory: Inventory` child node + register w/ SaveSystem (player-scoped saveable). Add `take_pickup(item_id, count)` helper. Add `mount_boat(boat: Boat)` and `dismount_boat()` helpers that swap active camera + transition action SM to Sail/Idle.
- `scripts/ai/target_dummy.gd` — on death, before `queue_free`, instance an `ItemPickup` w/ `item_id=&"scrap", count=1` at its position and add to parent. (Loot table comes later — this is one hardcoded drop.)
- `scripts/dev/test_island.gd` — instance `HUD.tscn` as a child; instance `Boat.tscn` near the shore at known offset, set its `water_y` to the placeholder water plane's Y; expand water plane to ~400 m × 400 m so there's somewhere to drive.
- `scripts/player/actionSM.gd` — register the new `Sail` state alongside existing Idle/Attack.
- `project.godot` — `interact`, `inventory`, `throttle_up/down`, `rudder_left/right` already in InputMap from Phase 1. Verify; no edit needed if Phase 1 was complete.

---

## Critical Implementation Notes

- **SkillManager level-up math.** Walk `xp_curve` cumulatively: level = 1 + count of thresholds whose cumulative sum ≤ `skills[id].xp`. Cap level at `xp_curve.size() + 1`. Emit `skill_leveled` only when `new_level > old_level` (handles big-XP-grant edge case where multiple levels jump at once — emit per level to keep toast clean).
- **Inventory stacking.** `add(item_id, count)` fills existing stacks of that id first up to `max_stack`, then opens new slots. Returns leftover count if inventory full (drop on ground? Phase 3: just print warn, no drop).
- **Pickup loop.** `ItemPickup`'s Area3D layer = player-pickup layer (new dedicated layer 4). Player's `CharacterBody3D` already on layer 1; add layer 4 to its collision_mask only on a tiny child Area3D, **not** the body — avoids false hitbox overlaps.
- **UI pause.** Inventory screen sets `get_tree().paused = true` on open, restores on close. Mark HUD nodes `process_mode = PROCESS_MODE_ALWAYS` so toasts still tick (or accept they freeze — fine for Phase 3).
- **Saveable persistence order.** Player's inventory must load *after* InventoryRegistry has scanned items. Both happen in `_ready`; SaveSystem.load_or_init runs from main.gd `_ready` which is *after* autoload _readys, so order is fine.
- **Test island sword still works as before.** Don't gate Phase 2 sword behind inventory equip — the existing weapon mount stays hardcoded.
- **Toast queue.** If multiple level-ups fire same frame (cross-skill), enqueue and play sequentially w/ ~1 s each. Don't stack visually.
- **Boat camera handoff.** Single `Camera3D.current = true` at a time. Player camera goes `current = false` on mount; boat camera flips on. Reverse on dismount. Don't free either — just toggle.
- **Boat mount race.** Player must be standing (movement SM in Idle/Run/etc., not Jump/Fall) to mount. Block mount if airborne to avoid mid-jump teleport into boat.
- **Boat-vs-island collision.** `move_and_slide` on `CharacterBody3D` handles it via the existing island `StaticBody3D` collider. No new collision layers needed — boat on layer 1 (world), masks layer 1.
- **Pinned Y is a lie.** Setting `position.y = water_y` after `move_and_slide` will fight the slide if boat hits a slope. Acceptable here (water is flat) but flag in code comment as the seam to fix when buoyancy lands.
- **Sail state input gating.** While Sail active, swallow `attack_light`/`attack_heavy` so player can't swing sword from boat. Movement actions go to boat throttle/rudder, not player locomotion.

---

## Reusable Phase 1–2 Hooks (Don't Re-Invent)

- `EventBus.skill_leveled` — declared in [event_bus.gd:7](globals/event_bus.gd:7). Wire toast listener.
- `EventBus.item_picked_up` — declared at [event_bus.gd:4](globals/event_bus.gd:4). Wire HUD pickup line.
- `SaveSystem.register(self)` pattern — already used by [skill_manager.gd:6](globals/skill_manager.gd:6); copy for player's `Inventory`.
- `InventoryRegistry._scan_items()` — already scans `data/items/*.tres` at [inventory_registry.gd:10](globals/inventory_registry.gd:10). Drop new ItemDef .tres files in and they appear automatically.
- `target_dummy.take_damage` — existing death hook at [target_dummy.gd:19](scripts/ai/target_dummy.gd:19) is the natural insert point for loot drop.
- Existing `interact` and `inventory` actions — already in InputMap from Phase 1 per arch.
- `throttle_up`, `throttle_down`, `rudder_left`, `rudder_right` — already in InputMap from Phase 1 per arch §"InputMap". Wire boat to these directly.
- Existing `actionSM` — add Sail state alongside Idle/Attack. No new state-machine harness needed.

---

## Verification

1. F5 → test island loads as before, plus HUD root in the tree and a boat in the water near shore.
2. Hit target dummy w/ sword. `[Dummy] hp=...` prints (Phase 2 behavior). Output panel also shows `damage_dealt` (Phase 2). After enough hits, Output shows `skill_leveled swords 2` and screen shows fading "Swords reached level 2" toast.
3. Dummy dies → small cube spawns at its position. Walk onto cube → disappears, sfx plays (placeholder), HUD shows "+1 scrap".
4. Press `I` → inventory screen opens, world pauses, scrap stack visible w/ count. Hover → tooltip shows display_name + description from `data/items/scrap.tres`.
5. Quit + relaunch → Swords level still 2, inventory still has the scrap.
6. Manually corrupt save (truncate to 0) → relaunch → game starts w/ defaults, no crash (Phase 1 invariant preserved).
7. **Boat:** walk up to boat, press `interact` → camera switches to boat-rear, player capsule hidden. `W` (throttle_up) accelerates forward, `S` reverses, `A`/`D` turn. Boat stays at constant water Y. Drive into island → boat stops on collider, doesn't ram through.
8. Press `interact` while sailing → player teleports to deck-side spawn, capsule visible, player camera active again. Boat coasts to stop.
9. Try to mount mid-jump → ignored (no mount race).
10. Try to swing sword while sailing → no swing (input gated).

---

## Out of Scope (Deferred)

- **Crafting stations + recipes (entire system).** Workbench, RecipeDef, RecipeResolver, crafting screen, station discovery, `DiscoveryLog.discover_station` — all deferred. May land in Phase 4.
- Equipping crafted weapons (weapon-swap on player's WeaponMount). Phase that owns equipment.
- Loot tables, weighted drops, rarity. Phase 3 hardcodes one drop. Real `LootTable` resource lands w/ real enemies.
- Map screen, skill screen, settings menu. Just inventory + toasts this phase.
- Hotbar, drag-drop reorder, item drop-from-inventory. Inventory is read-only-grid this phase.
- Streaming, biomes, real enemies (those phases come after).
- Boat buoyancy / wave riding — needs ocean shader (Phase 8).
- Boat inventory (cargo chest) — Phase 8 alongside the rewrite.
- Boat persistence (position, rotation, HP) — Phase 8.
- Boat HP / sinking / cannons / naval combat — Phase 9.
- Multiple boats / craftable boats — Phase 8+. Phase 3 ships exactly one pre-placed boat.
- Wandering enemy ships — Phase 9.

---

## Critical Files Reference

Files most likely to break or need careful review during implementation:

- [globals/skill_manager.gd](globals/skill_manager.gd) — level-up math added; touches existing save shape.
- [globals/save_system.gd](globals/save_system.gd) — no edits, but new Saveable (player `Inventory`) flows through it.
- [scripts/player/player.gd](scripts/player/player.gd) — gains inventory child + pickup helper + mount/dismount helpers.
- [scripts/ai/target_dummy.gd](scripts/ai/target_dummy.gd) — death hook spawns pickup.
- [scripts/dev/test_island.gd](scripts/dev/test_island.gd) — adds HUD + Boat instances; expands water plane.
- [scripts/player/actionSM.gd](scripts/player/actionSM.gd) — registers Sail state.

---

## Execution Order

1. Apply 6 architecture edits to `ARCHITECTURE.md`.
2. Create `SkillDef`, `ItemDef` script classes + first `.tres` resources (skills + scrap + sword reference).
3. Extend `SkillManager` w/ curve walk + `skill_leveled` emit. Verify in Output by spamming sword hits.
4. Build `Inventory` node + attach to player + Saveable. Verify add/remove via debugger.
5. Build `ItemPickup` + wire dummy death drop. Verify scrap on ground + pickup → inventory.
6. Build HUD + SkillToast + pickup line. Verify toasts on level-up and on pickup.
7. Build InventoryScreen. Verify toggle, pause, tooltips.
8. Build `Boat.tscn` + boat.gd standalone — drop into test_island, drive w/ debug autoload of inputs. Verify glides on flat water, stops on island.
9. Add Sail action state + mount/dismount helpers + boat camera handoff. Verify mount/dismount loop, input gating, no mid-jump mount.
10. Expand water plane in test_island. Verify boat can roam.
11. Run 10-step verification end-to-end.
12. Commit: "Phase 3: skill curves + inventory + basic boat".
