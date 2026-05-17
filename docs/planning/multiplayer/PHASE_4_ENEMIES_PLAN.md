# Phase 4 — Server-Authoritative Enemies

## Context

Mingusbreath's multiplayer retrofit is done through phases 0–3, 5, 6, 7, 8, 9.
Phase 4 (enemies) was skipped. Enemies (`Husk`, `TargetDummy`) currently run
fully client-local AI and only appear in `scripts/dev/test_island.gd` — a dev
scene that is **not** part of the multiplayer flow (`LobbyMenu` → `World.tscn`).

This phase makes enemies multiplayer-safe: the host runs all enemy AI and the
result replicates to every peer, so all players see the same enemy at the same
place doing the same thing, and damage/loot resolve consistently.

## Decisions (confirmed)

- **Spawn**: no production spawn system. The host debug-spawns a small test
  batch of `Husk`s near the mainland at world load, via a `MultiplayerSpawner`.
- **Persistence**: none. Debug-spawned enemies respawn each session.
- **Loot**: enemy loot drops as real `ItemPickup` nodes, server-spawned via a
  `MultiplayerSpawner`, collectable by any nearby player (server decides).

## Authority model

- Enemies spawn from the host via `MultiplayerSpawner` → their multiplayer
  authority defaults to the server (peer 1) on every peer. No name-parsing
  needed (unlike `Player`, whose authority is the owning client).
- Host runs enemy physics + AI. Clients freeze the AI and display the
  replicated transform / hp / telegraph state.
- Pickups likewise are server-authoritative, spawned by the host.

---

## Changes

### 1. `scenes/world/World.tscn` — spawn containers

Add alongside the existing `Players` / `PlayerSpawner` and `Boats` /
`BoatSpawner`:

```
[node name="Enemies" type="Node3D" parent="."]
[node name="EnemySpawner" type="MultiplayerSpawner" parent="."]
_spawnable_scenes = PackedStringArray("res://scenes/enemies/Husk.tscn")
spawn_path = NodePath("../Enemies")
spawn_limit = 32

[node name="Pickups" type="Node3D" parent="."]
[node name="PickupSpawner" type="MultiplayerSpawner" parent="."]
spawn_path = NodePath("../Pickups")
spawn_limit = 64
```

`PickupSpawner` needs `ItemPickup` as a spawnable scene. `ItemPickup` is
currently script-only (instantiated via `ItemPickup.new()` — see
`scripts/items/item_pickup.gd`, `scripts/enemies/enemy.gd:71`). Create a thin
`scenes/items/ItemPickup.tscn` (root `Area3D` + the script + a
`MultiplayerSynchronizer`) so the spawner can replicate it; register it in
`PickupSpawner._spawnable_scenes`.

### 2. `scenes/enemies/Husk.tscn` + `TargetDummy.tscn` — replication

Add a `MultiplayerSynchronizer` child (`NetSync`) to each, replicating:
- `position`, `rotation` — mode 1 (always, 20 Hz: `replication_interval = 0.05`)
- `hp` — mode 2 (on_change)
- `telegraphing` (new bool on `enemy.gd`, see §3) — mode 2

`TargetDummy` is a `StaticBody3D` — only `hp` needs replicating (it doesn't
move), but include `position` for safety.

### 3. `scripts/enemies/enemy.gd` — server-authoritative

- Add `var telegraphing: bool = false` (replicated; the attack state sets it so
  clients can show the telegraph tint).
- `_ready()`: after the existing setup, gate clients:
  ```gdscript
  if not multiplayer.is_server():
      set_physics_process(false)
      attack_hitbox.monitoring = false
  ```
  This stops both state machines (`movementSM` / `actionSM` are driven only by
  `enemy._physics_process` at `enemy.gd:48-51` — they have no own
  `_physics_process`, so disabling this is sufficient).
- `take_damage(amount, source)`: route to the authority, mirroring
  `Player.take_damage` (`scripts/player/player.gd`):
  ```gdscript
  func take_damage(amount, source = null):
      if not is_multiplayer_authority():
          var sp: NodePath = source.get_path() if source is Node else NodePath()
          rpc_id(get_multiplayer_authority(), "take_damage_rpc", amount, sp)
          return
      hp -= amount
      _flash.rpc()                       # see below
      if hp <= def.flee_hp_ratio * def.max_hp and hp > 0.0:
          movementSM.transition_to("flee")
      if hp <= 0.0:
          _die(source)

  @rpc("any_peer", "reliable")
  func take_damage_rpc(amount, source_path):
      if not is_multiplayer_authority():
          return
      take_damage(amount, get_node_or_null(source_path))

  @rpc("authority", "reliable", "call_local")
  func _flash():
      DamageFlash.flash(mesh)
  ```
  The `_flash` RPC replaces the direct `DamageFlash.flash(mesh)` so every peer
  sees the hit flash.
- `_die(source)`: server-only (only reached on the authority via `take_damage`).
  Replace the local `EventBus.enemy_killed.emit` with the networked twin (§6):
  `NetworkManager.broadcast_enemy_killed(def.id, source)`. Keep `_drop_loot()`
  then `queue_free()` (the spawner replicates the despawn).
- `_drop_loot()`: server-only. Spawn pickups via the shared helper (§5) into
  `/WorldRoot/Pickups` instead of `get_parent().add_child`.
- `get_player()` (`enemy.gd:80`): currently returns `get_nodes_in_group("player")[0]`
  — only the **local** peer's player is in that group, so server enemies would
  see at most the host. Replace with a nearest-of-all-players search over
  `/WorldRoot/Players` children:
  ```gdscript
  func get_player() -> Node3D:
      var scene := get_tree().current_scene
      if scene == null: return null
      var players := scene.get_node_or_null("Players")
      if players == null: return null
      var best: Node3D = null
      var best_d := INF
      for c in players.get_children():
          var d := global_position.distance_to((c as Node3D).global_position)
          if d < best_d:
              best_d = d; best = c
      return best
  ```
  Every movement/action state calls `enemy.get_player()` (chase, flee, idle,
  patrol, return, sense, action_idle, attack) — fixing this one method fixes
  targeting everywhere.

### 4. `scripts/enemies/enemy_states/action_state/attack.gd` — networked hit

- `_on_hitbox_entered` runs server-only already (the action SM ticks only via
  the server-gated `enemy._physics_process`). Replace:
  - `EventBus.damage_dealt.emit(enemy, target, &"", &"", amount)` →
    `NetworkManager.broadcast_damage(enemy, target, &"", &"", amount)` (the
    networked helper added in Phase 9).
  - `target.take_damage(amount, enemy)` stays — `Player.take_damage` already
    RPC-routes to the target player's authority.
- Telegraph: `_set_telegraph_visual(on)` currently sets `enemy.mesh` material
  directly (server-only). Set `enemy.telegraphing = on` as well; have each peer
  apply the tint by watching that replicated bool (small `_process` on
  `enemy.gd`, or move `_set_telegraph_visual` into `enemy.gd` driven by a
  `telegraphing` setter). Recommended: a `telegraphing` setter on `enemy.gd`
  that applies/clears the red material — runs on every peer when replicated.
- `_on_player_parried`: the enemy (server) must hear the parry. Today
  `player_parried` is emitted locally on the parrying player's peer
  (`Player.take_damage`), so a guest's parry never reaches the server. Fix in
  §7 (networked `player_parried`).

### 5. `scripts/items/item_pickup.gd` + `scenes/items/ItemPickup.tscn` — server-auth pickups

- New `ItemPickup.tscn`: `Area3D` root + `item_pickup.gd` + `NetSync`
  (`MultiplayerSynchronizer` replicating `position`, `item_id`, `count`).
- `item_pickup.gd`:
  - `_process` chase logic + `_on_body_entered` → server-only
    (`if not multiplayer.is_server(): return`). Clients just display the
    replicated position.
  - On collect: instead of `_target.take_pickup(item_id, count)` directly,
    call it through the player's authority. `Player.take_pickup` currently does
    `inventory.add` + `EventBus.item_picked_up.emit`. Make `take_pickup` an
    `@rpc("any_peer","reliable","call_local")` that runs on the player's
    authority (guard `if not is_multiplayer_authority(): return`), so the
    server can award the item to any player; then `queue_free()` the pickup
    (spawner replicates the despawn).
  - Replace the `ItemPickup.new()` construction sites with
    `load("res://scenes/items/ItemPickup.tscn").instantiate()`.
- A shared `BoatManager`-style spawn helper, or a `PickupManager`/static
  function, that adds a configured `ItemPickup` to `/WorldRoot/Pickups` on the
  server. Used by `enemy.gd._drop_loot`, `target_dummy.gd._drop_loot`, and
  `WorldStream._apply_near_deltas` (`globals/world_stream.gd:151` — also
  constructs `ItemPickup.new()`).
- `target_dummy.gd`: `take_damage` server-auth (same routing as enemy);
  `_drop_loot` server-only via the helper; `enemy_killed` networked (§6).

### 6. `globals/network_manager.gd` — networked `enemy_killed`

Mirror the existing `broadcast_damage` / `_damage_event` pair (added in
Phase 9):
```gdscript
func broadcast_enemy_killed(enemy_id: StringName, killer: Node) -> void:
    var kp: NodePath = killer.get_path() if killer != null else NodePath()
    if multiplayer.multiplayer_peer == null:
        EventBus.enemy_killed.emit(enemy_id, killer); return
    _enemy_killed_event.rpc(enemy_id, kp)

@rpc("any_peer", "reliable", "call_local")
func _enemy_killed_event(enemy_id, killer_path):
    EventBus.enemy_killed.emit(enemy_id, get_node_or_null(killer_path))
```

### 7. `scripts/player/player.gd` — networked `player_parried`

`Player.take_damage` emits `EventBus.player_parried.emit(source)` locally. The
attacking enemy lives on the server; a guest's parry must reach it. Add a
networked twin (same pattern), e.g. `NetworkManager.broadcast_parried(attacker)`
→ `_parried_event` RPC re-emitting `EventBus.player_parried` on all peers.
`attack.gd._on_player_parried` then fires on the server and staggers the enemy.

### 8. `globals/network_manager.gd` — debug enemy batch

Add a host-only debug spawn. At world load (in `register_world_root`, after
players spawn) or behind a debug key:
```gdscript
const HUSK_SCENE := "res://scenes/enemies/Husk.tscn"

func debug_spawn_enemies(count: int = 3) -> void:
    if not multiplayer.is_server() or _world_root == null:
        return
    var enemies := _world_root.get_node_or_null("Enemies")
    var mp := IslandRegistry.get_mainland_placement()
    if enemies == null or mp == null:
        return
    for i in count:
        var e := load(HUSK_SCENE).instantiate()
        e.name = "Husk_%d" % i
        var ang := TAU * float(i) / float(count)
        e.position = mp.position + Vector3(cos(ang), 20.0, sin(ang)) * 12.0
        enemies.add_child(e, true)
```
Call it once after the initial player spawn batch. Keep behind an
`F`-key debug toggle or a `--debug-enemies` cmdline flag if auto-spawn is
undesirable.

### 9. `scripts/dev/test_island.gd`

Dev sandbox — not in the MP flow. Its `_spawn_husks` / `_spawn_dummies` use
`ItemPickup.new()` indirectly via enemy loot. After §5, `ItemPickup` is a
scene; the dev script still works offline (`multiplayer.is_server()` is true
when offline, so server-gated code runs). No functional change required, but
verify it still parses after the `enemy.gd` / `item_pickup.gd` edits.

---

## Critical files

| File | Change |
|------|--------|
| `scenes/world/World.tscn` | `Enemies`+`EnemySpawner`, `Pickups`+`PickupSpawner` |
| `scenes/enemies/Husk.tscn`, `TargetDummy.tscn` | add `MultiplayerSynchronizer` |
| `scenes/items/ItemPickup.tscn` | NEW — scene wrapper for the spawner |
| `scripts/enemies/enemy.gd` | server-gated AI, `take_damage` RPC routing, `telegraphing`, `_flash` RPC, `get_player` all-players, networked death/loot |
| `scripts/enemies/target_dummy.gd` | server-auth damage, networked kill, helper-based loot |
| `scripts/enemies/enemy_states/action_state/attack.gd` | `broadcast_damage`, `telegraphing`, networked parry reaction |
| `scripts/items/item_pickup.gd` | server-auth chase/collect, RPC award, scene-based |
| `globals/network_manager.gd` | `broadcast_enemy_killed`, `broadcast_parried`, `debug_spawn_enemies` |
| `globals/world_stream.gd` | `_apply_near_deltas` uses the new pickup helper |
| `scripts/player/player.gd` | networked `player_parried`, `take_pickup` as RPC |

Reuse: `broadcast_damage`/`_damage_event` (network_manager.gd, Phase 9) is the
template for the new `enemy_killed` / `player_parried` twins. `Player.take_damage`
RPC routing is the template for `Enemy.take_damage`. `BoatManager._spawn_boat`
is the template for the pickup spawn helper.

---

## Verification

Two-instance ENet test (`--offline --host` / `--offline --join 127.0.0.1`):

1. **Spawn** — host enters world; 3 Husks appear near mainland on **both**
   windows at the same positions.
2. **AI sync** — a Husk chases the nearest player; both windows show the same
   target, same path, same hp.
3. **Server damage** — guest attacks a Husk; its hp drops on both screens; the
   damage flash plays on both.
4. **Enemy attack** — Husk hits a player; that player's hp drops (their HUD);
   telegraph tint shows on both windows.
5. **Parry** — guest parries a Husk's strike; the Husk staggers on both windows
   (proves `player_parried` reached the server).
6. **Loot** — kill a Husk; an `ItemPickup` spawns, visible to both; whichever
   player walks over it gets the item in their inventory only; the pickup
   disappears for both.
7. **Death sync** — killed Husk disappears on both windows; `enemy_killed`
   fires on both (skill XP / UI hooks).
8. **Disconnect** — guest disconnects mid-fight; Husks retarget the host with
   no crash.

Offline regression: `Solo (Offline)` — `debug_spawn_enemies` still spawns (host
path; offline counts as server), enemies behave as before.
