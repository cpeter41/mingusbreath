# Phase 4 Plan — Combat Depth + Real Enemies

## Context

Phase 3 closed the progression-loop slice (skill XP curves, inventory, basic boat). Combat exists but has no stakes — target dummies don't fight back, HP/stamina are unread variables on the player, skills level up but don't multiply damage. Crafting was deliberately cut from the roadmap.

Phase 4 turns combat into a survival loop: HP and stamina become real resources, the player can die and respawn, attacks/sprint/jump drain stamina, a single biome-agnostic enemy type chases and attacks the player, dies, drops loot. Block + dodge action states give the player meaningful defensive options. Skill damage multipliers actually apply now that levels mean something.

Naval combat, time of day, world streaming, ranged combat, and biome-keyed spawn tables all stay deferred — those depend on world systems that don't exist yet.

This is arch [Implementation Order](ARCHITECTURE.md) step 5 (combat depth — block/dodge/stamina) + a sliver of step 9 (enemy AI without the biome/spawn-table machinery).

---

## Deliverables

After F5 on the existing test island:

1. **HUD HP + stamina bars** — top-left corner, simple `ProgressBar` widgets, listen to player signals.
2. **Stamina drain** — sprint (8/sec), light attack (10), heavy attack (25), jump (15), dodge (20), block (5/sec while incoming damage). Regens 15/sec when idle (no recent action).
3. **Stamina gating** — light/heavy attack blocked when stamina < cost. Sprint forced off when stamina hits 0.
4. **Husk enemy** — first real enemy. Spawned in test island alongside (not replacing) one target dummy. FSM: Idle → Patrol → Sense → Chase → Attack → Flee (low HP) → Return.
5. **Husk attack** — telegraph (~0.4s wind-up w/ red flash) → strike → cooldown. Hits player for HP damage.
6. **Player death + respawn** — HP ≤ 0 → fade-to-black → respawn at world origin (0, 15, 0), full HP/stamina, inventory + skills preserved.
7. **Block action state** — held action; incoming damage × 0.2; stamina drain while taking hits; first 0.15s = parry window (full negate + stagger attacker).
8. **Dodge action state** — directional roll, ~0.4s i-frames (hurtbox disabled), 20 stamina cost up front.
9. **Skill damage multipliers** — `final = base * (1 + 0.1 * (level - 1))`. CombatResolver actually applies it.
10. **Enemy loot drop** — husk drops scrap on death via existing `ItemPickup`.
11. **Save round-trip** — inventory + skills persist; HP/stamina + dead enemies do **not** persist (reset on load — by design).

---

## Architecture Edits (apply to `ARCHITECTURE.md` first)

1. **Pin EnemyDef shape.** Arch §"Enemy AI" references enemy stats but no schema. Add: `id: StringName, display_name: String, max_hp: float, damage: float, move_speed: float, sense_radius: float, attack_range: float, attack_cooldown: float, flee_hp_ratio: float = 0.2, loot_drops: Array[StringName] = []`. Multipliers + biome tier deferred.
2. **Pin stamina cost table.** Add a new subsection in §"Player & Combat": `Canonical stamina costs (tunable, schema is stable): light_attack=10, heavy_attack=25, sprint=8/sec, jump=15, dodge=20, block=5/sec while taking hits, regen=15/sec when idle for >0.5s.`
3. **Document Block + Dodge as live action states.** Arch §"Player & Combat" lists them but the phase note says only Idle/Run/Sprint/Jump/Fall/Attack are implemented. Update: Phase 4 implements Block + Dodge as parallel `actionSM` states alongside Attack.
4. **Enemy state machine pattern.** Add to §"Enemy AI": `Per-instance FSM (Idle/Patrol/Sense/Chase/Attack/Flee/Return). Single state machine — no movement/action split. Mirror the player's actionSM/movementSM split is overkill for AI.`
5. **Player death model.** Add to §"Player & Combat": `On HP ≤ 0, player respawns at world origin with full HP/stamina. Inventory + skills preserved. No item drops on death. HP and stamina are not persisted across save/load — they reset to max on every load.`
6. **CombatResolver multipliers.** Replace the Phase 2 placeholder note in §"Player & Combat" CombatResolver contract: `Phase 4 applies skill_def.per_level_damage_mult linearly: final = base_damage * (1 + 0.1 * (level - 1)). Future tuning moves the formula or per-skill curves into SkillDef.`

---

## Files to Create

### Data resources

- `scripts/data/enemy_def.gd` — `class_name EnemyDef extends Resource`, fields per arch edit #1.
- `data/enemies/husk.tres` — first enemy (max_hp=40, damage=8, move_speed=3.5, sense_radius=12, attack_range=1.8, attack_cooldown=2.0, flee_hp_ratio=0.2, loot_drops=[&"scrap"]).

### Scripts (enemy AI)

- `scripts/ai/enemy.gd` — `class_name Enemy extends CharacterBody3D`. Holds `EnemyDef` ref, current HP, FSM ref. Builds hitbox + hurtbox in `_ready` (or via .tscn).
- `scripts/ai/enemy_states/state.gd` — base class w/ `enter()`, `exit()`, `physics_update(delta)`, `handle_input(event)`.
- `scripts/ai/enemy_states/idle.gd` — small wait, then transition to Patrol.
- `scripts/ai/enemy_states/patrol.gd` — wander between random points within ~10m of spawn anchor.
- `scripts/ai/enemy_states/sense.gd` — sphere check for player; if in range → Chase. (Sight cone deferred.)
- `scripts/ai/enemy_states/chase.gd` — move toward player; transition to Attack when in `attack_range`.
- `scripts/ai/enemy_states/attack.gd` — telegraph → strike → cooldown. Strike calls `CombatResolver.resolve` against player hurtbox.
- `scripts/ai/enemy_states/flee.gd` — when HP ≤ `flee_hp_ratio * max_hp`, run away from player for N seconds.
- `scripts/ai/enemy_states/return.gd` — return to patrol anchor when player out of sense range for N seconds.

### Scripts (player combat extensions)

- `scripts/player/action_states/block.gd` — held state; sets `is_blocking` flag; consumes stamina when hit; tracks parry window.
- `scripts/player/action_states/dodge.gd` — burst movement in input direction; disables hurtbox for ~0.4s; up-front stamina cost.

### Scripts (UI)

- `scripts/ui/stat_bar.gd` — reusable `ProgressBar` wrapper w/ tween + color interpolation. Accepts `bind_to(signal_name)` so HUD can wire HP and stamina with the same widget.

### Scenes

- `scenes/ai/Husk.tscn` — `CharacterBody3D` root w/ placeholder humanoid mesh (capsule + smaller capsule for head, dark grey). `CollisionShape3D`. `Hurtbox` (Area3D) for taking player hits. `AttackHitbox` (Area3D, monitoring=false until strike frame) on a forward-mounted bone-equivalent. State machine node attached.

---

## Modifications to Existing Files

- `scripts/player/player.gd` — promote `hp` and `stamina` from inert vars to driven state. Emit `EventBus.player_hp_changed`/`player_stamina_changed` on every change. Add `take_damage(amount, source)`, `consume_stamina(amount) -> bool`, `_regen_stamina(delta)`, `die()`, `respawn()`. Wire stamina costs into existing movement/action states (sprint drain, attack cost gate, jump cost).
- `scripts/player/actionSM.gd` — register Block + Dodge alongside Idle/Attack. No new harness.
- `scripts/combat/combat_resolver.gd` — apply skill multiplier: `final = base * (1.0 + 0.1 * (SkillManager.get_level(skill_id) - 1))`.
- `scripts/ui/hud.gd` — mount two `StatBar` widgets, top-left, listening to `EventBus.player_hp_changed` and `player_stamina_changed`. Mount a fade-to-black `ColorRect` on a high CanvasLayer for death transitions.
- `scripts/dev/test_island.gd` — replace two of the three target dummies with husks; keep one dummy for skill-grinding XP without dying. Spawn husks ~8m from player on land.
- `globals/event_bus.gd` — add signals: `player_hp_changed(hp: float, max_hp: float)`, `player_stamina_changed(stamina: float, max_stamina: float)`, `player_died()`, `player_respawned()`.

---

## Critical Implementation Notes

- **HP/stamina not persisted.** Reset to max on `_ready` and after respawn. Save schema unchanged — no migration needed.
- **Respawn point.** Hardcoded to (0, 15, 0). Real respawn-anchor system (bedroll, last-rested-spot) is a later phase concern.
- **Stamina regen gate.** Track `time_since_last_stamina_use`; only regen if > 0.5s since last cost. Prevents free chained sprint-attack spam.
- **Block math.** Damage taken while blocking = `incoming * 0.2`. Stamina drained = `incoming * 0.5` (so a heavy hit drains ~5–10 stamina). Block stops working at stamina = 0.
- **Parry window.** First 0.15s of holding block = parry. Successful parry: 0 damage, husk enters a 1.5s `Stagger` substate (extension to Attack state) where it can't strike.
- **Dodge i-frames.** Player hurtbox `monitoring = false` for the dodge animation duration (~0.4s). Stamina cost paid up front; if can't pay, dodge is blocked.
- **Husk attack telegraph.** `_attack_state.enter()` → set hitbox material to red flash → wait 0.4s → enable hitbox monitoring for 0.15s strike → disable → cooldown 2.0s. Player has time to react.
- **Husk navigation.** Phase 4: simple `move_toward(player.position)` ignoring obstacles for chase. Will get stuck on terrain edges — acceptable. Real Navigation3D / NavMesh later.
- **Land-locked husks.** Husk doesn't path into water (raycast down, if no terrain → don't move there). Avoids husks walking into the ocean toward a boat.
- **Player death camera.** Not switching cameras. Just fade `ColorRect.modulate.a` from 0 → 1 over 0.6s, teleport, restore HP, fade back.
- **Skill multiplier formula.** `combat_resolver.gd` returns `base * (1.0 + 0.1 * (level - 1))`. Stored in `SkillDef.per_level_damage_mult` for future tuning (currently 1.0, unused — Phase 4 hardcodes the 0.1 coefficient; real per-skill scaling is later).
- **Inventory full on enemy death.** `Inventory.add` already returns leftover; HUD pickup line shows the item, leftover items just don't spawn (no on-ground drop yet).
- **Dead husks not persisted.** Save doesn't track which enemies died. They respawn on relaunch. Real per-chunk dead-flag store comes with world streaming.

---

## Reusable Phase 1–3 Hooks (Don't Re-Invent)

- `EventBus` — add new signals here, follow existing pattern at [event_bus.gd](globals/event_bus.gd).
- `SaveSystem.register` — used by `Inventory`, `SkillManager`. **Not** used for HP/stamina (transient by design).
- `ItemPickup` — reuse for husk loot drops, no new pickup script needed. Same death-hook pattern as [target_dummy.gd:18](scripts/ai/target_dummy.gd:18).
- `actionSM` — register Block + Dodge alongside Idle/Attack. Existing harness in [actionSM.gd](scripts/player/actionSM.gd).
- `Hitbox` / `Hurtbox` / `CombatResolver` — already wired for player→dummy. Same flow for husk→player and player→husk.
- `SkillManager.add_xp` — existing call site in [combat_resolver.gd](scripts/combat/combat_resolver.gd) keeps working.
- `InventoryRegistry.get_item` — for loot lookup ([inventory_registry.gd:24](globals/inventory_registry.gd:24)).
- **EnemyDef scan-on-startup** — same pattern as `SkillDef`/`ItemDef`. Phase 4 has only one enemy type so a dedicated `EnemyRegistry` autoload is overkill; load `husk.tres` directly in test_island.gd.
- HUD `process_mode = PROCESS_MODE_ALWAYS` already set in [hud.gd](scripts/ui/hud.gd) — death fade ColorRect inherits this so it ticks during pause.

---

## Verification

1. F5 → HP + stamina bars top-left, both full. Husks visible on island.
2. Sprint across island → stamina drains; release sprint, wait → stamina regens.
3. Spam light attacks → stamina drops; at low stamina, attacks blocked (no swing).
4. Walk near husk (within sense_radius) → husk transitions to Chase, runs at player.
5. Husk closes distance → enters Attack, telegraphs (red flash), strikes → player HP visibly drops.
6. Hold block during husk strike → take 20% damage, stamina drains.
7. Time block to husk strike (within 0.15s of input → impact) → parry triggers, husk stutters, no damage.
8. Dodge during incoming attack → roll, no damage taken (i-frames). Costs 20 stamina.
9. Kill husk → scrap drops on ground, walk into it → "+1 Scrap" HUD line, inventory updated.
10. Hit dummy w/ leveled-up Swords (from Phase 3 grinding) → damage clearly higher than at level 1 (verify via `[damage_dealt]` debug print or HP-drop math).
11. Let husk kill player → fade to black, respawn at origin with full HP/stamina, inventory and skills intact.
12. Quit + relaunch → HP/stamina full, inventory + skills persist (per Phase 3 save round-trip).

---

## Out of Scope (Deferred)

Candidates for **Phase 5**:
- **Time of day + day/night spawn tables** — `TimeOfDay` autoload ticks; sun rotation; night spawns harder husks (or different enemy). Atmosphere + variance.
- **World streaming + multiple islands** — chunked terrain loading around player, real biome assignment, multiple islands separated by ocean. Highest engineering lift; unlocks real exploration loop.

Candidates for **Phase 6+**:
- **Ranged combat (bow + arrow projectiles)** — needs projectile pooling.
- **Multiple enemy types + biome-keyed spawn tables** — wait for world streaming + TimeOfDay.
- **Bosses + boss anchors** — wait for biome system.
- **Naval combat / cannons / boat HP** — Phase 8+ alongside ocean shader rewrite of boat (already deferred from Phase 3).
- **Real respawn flow** — bedroll, last-rested-anchor, save the spawn point.
- **Item drops on player death** — economy friction, defer until economy is tighter.
- **Crafting** — explicitly cut from roadmap. Not coming back unless reconsidered.

---

## Critical Files Reference

Files most likely to break or need careful review:

- [scripts/player/player.gd](scripts/player/player.gd) — HP/stamina logic + death/respawn. Touches existing movement/action wiring.
- [scripts/player/actionSM.gd](scripts/player/actionSM.gd) — registering Block + Dodge.
- [scripts/combat/combat_resolver.gd](scripts/combat/combat_resolver.gd) — skill multiplier formula. Affects all damage in the game.
- `scripts/ai/enemy.gd` (new) — base for all enemies; FSM bugs here cascade.
- [scripts/ui/hud.gd](scripts/ui/hud.gd) — bar widgets + death fade overlay.
- [globals/event_bus.gd](globals/event_bus.gd) — new signals must match listener signatures exactly.

---

## Execution Order

1. Apply 6 architecture edits to `ARCHITECTURE.md`.
2. Create `EnemyDef` script class + `data/enemies/husk.tres`.
3. Promote player HP/stamina to live fields. Add EventBus signals + StatBar HUD widgets. Verify drain on sprint/jump/attack.
4. Add Block action state + parry window. Verify damage reduction + parry stagger placeholder.
5. Add Dodge action state + i-frames. Verify roll + invulnerability window.
6. Apply skill multiplier in CombatResolver. Verify level-2 Swords does noticeably more damage.
7. Build `Enemy` base + state machine harness. Empty states stubbed.
8. Implement Idle → Patrol → Sense → Chase. Verify husk runs at player.
9. Implement Attack state w/ telegraph + strike. Verify player takes damage.
10. Implement Flee + Return states. Verify low-HP husk runs away, then returns to patrol.
11. Wire husk death → loot drop using existing `ItemPickup`.
12. Player death detection + fade-to-black + respawn at origin. Verify full loop.
13. Wire husks into `test_island.gd`; keep one dummy for XP grinding.
14. Run 12-step verification end-to-end.
15. Commit: `"Phase 4: combat depth + real enemies"`.
