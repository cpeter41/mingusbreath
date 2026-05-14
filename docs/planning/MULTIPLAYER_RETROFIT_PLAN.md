# Mingusbreath Multiplayer Retrofit Plan

## Context

Mingusbreath is a Godot 4.6 single-player 3D open-world game (~4 km² ocean, 12 streamed islands, melee combat, boats). Zero multiplayer code exists today — every system mutates state locally and assumes one player. We are retrofitting **2–4 player host-authoritative co-op** over **Steam Networking** (GodotSteam), with **host-owned world save** + **per-guest local profiles** (skills, inventory).

This document is the full structural plan. It is written so a coding agent (including lower-capability models) can execute each step in order with minimal interpretation. Every step lists the **files**, **symbols**, and **acceptance criteria**. Read the *Authority Rules* section once before starting any phase — they govern every decision downstream.

---

## Architectural Decisions (Locked)

| Concern | Decision |
|---|---|
| Topology | Host-authoritative listen server (host is `multiplayer.is_server()` and also a local player) |
| Player count | 1–4 |
| Transport | GodotSteam `SteamMultiplayerPeer` (lobby-based, P2P via Steam relay) |
| World persistence | Host owns world save (`user://save.dat` on host). Guests own a separate local profile (`user://profile.dat`) holding skills + inventory. |
| Authority model | Server is authoritative for: world state, enemies, NPCs, damage, hit detection, pickups, boat physics, time-of-day, island streaming decisions, loot rolls. Each client owns: their own input (sent to server), camera, UI, audio, local prediction of own movement. |
| Tick rate | Physics 60 Hz (Godot default). Network send rate 20 Hz (every 3rd physics tick) for movement/AI. |
| Lag compensation | Simple client-side prediction + server reconciliation for own player. Server-side rewind for melee hit detection (rewind player + target snapshots ~100 ms back). |

---

## Authority Rules (read first, apply everywhere)

When in doubt, follow these rules verbatim. They are the contract every system in this codebase must follow after the retrofit.

1. **Server owns truth for shared state.** HP, position of enemies, item drops, world time, island deltas, kill credits, skill XP grants (server *grants*; client *displays*).
2. **Clients own intent.** Movement input, look direction, attack/block button presses. These travel client → server every frame as small RPCs (or via `MultiplayerSynchronizer` for the look vector). Server applies them.
3. **Never trust client position for damage.** A client says "I swung my sword." Server checks the swing on the server-side player transform (with rewind) and applies damage. Client damage code only **predicts** visual feedback.
4. **Every script that mutates shared state checks `multiplayer.is_server()` first.** If false, return. Mutations propagate via `MultiplayerSynchronizer` replication or explicit `@rpc` calls.
5. **Every spawned scene that exists on all peers must spawn via `MultiplayerSpawner`** on the server. Never `add_child` shared objects on a client.
6. **`@rpc` annotations are explicit.** Pick `authority` (server only calls clients), `any_peer` (clients call server), `call_local` (also run on caller), `reliable` vs `unreliable_ordered`. Never use the default unannotated.
7. **Local-only nodes** (UI, camera, local audio, particles, local input handler) are children of a `LocalOnly` group node, never replicated.
8. **EventBus stays local.** Signals fire on each peer independently. The server emits *its* events; clients emit *theirs*. Don't try to network the EventBus. Instead, route shared events via explicit RPCs that emit the local signal on each peer.

---

## Phase 0 — Dependencies & Project Settings

**Goal:** GodotSteam installed; project recognizes multiplayer; new autoloads stubbed.

### Steps
1. Install GodotSteam 4.x for Godot 4.6 (https://godotsteam.com/). Place `addons/godotsteam/` inside the project. Enable in `Project Settings → Plugins`.
2. Add `steam_app_id = 480` (Spacewar test ID) to a new `steam_appid.txt` next to `project.godot` for dev runs.
3. Append to `project.godot` `[autoload]` block, in this order (order matters — these depend on earlier autoloads):
   ```
   SteamLobby="*res://globals/steam_lobby.gd"
   NetworkManager="*res://globals/network_manager.gd"
   AuthorityRouter="*res://globals/authority_router.gd"
   ```
   Insert **after** `EventBus` and **before** `SaveSystem`. Updated order:
   ```
   EventBus, SteamLobby, NetworkManager, AuthorityRouter, Ocean, SaveSystem, GameState, ...
   ```
4. Create empty files at those paths now (real impl in later phases). Each should `extends Node` and have a `_ready()` that prints its name.
5. Add a new collision layer in `project.godot`: `Layer 5: NetGhost` (used for server-side rewind ghosts of player hitboxes).

### Acceptance
- Project launches without errors.
- New autoloads print on startup.

---

## Phase 1 — NetworkManager + Steam Lobby

**Files to create:**
- `globals/network_manager.gd`
- `globals/steam_lobby.gd`
- `scenes/ui/lobby_menu.tscn` + `scripts/ui/lobby_menu.gd`

### `globals/steam_lobby.gd`
Thin wrapper around GodotSteam lobby APIs. Responsibilities:
- `host_lobby(max_players: int = 4) -> void` — calls `Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_players)`. On `lobby_created` signal, store `lobby_id` and call `NetworkManager.start_host()`.
- `join_lobby(lobby_id: int) -> void` — `Steam.joinLobby(lobby_id)`. On `lobby_joined`, call `NetworkManager.start_client(lobby_owner_steam_id)`.
- `leave_lobby() -> void` — `Steam.leaveLobby(lobby_id)`, tell NetworkManager to disconnect.
- Signals: `lobby_ready(lobby_id)`, `lobby_joined(host_steam_id)`, `lobby_left`.

### `globals/network_manager.gd`
The single source of truth for peer/multiplayer state. Implements:
```
signal peer_player_joined(peer_id: int, steam_id: int)
signal peer_player_left(peer_id: int)
signal network_ready                        # emitted once peer is up
signal mode_changed(is_host: bool)

enum Mode { OFFLINE, HOST, CLIENT }
var mode: Mode = Mode.OFFLINE
var local_peer_id: int = 1                  # 1 if host, assigned by server if client
var peers: Dictionary = {}                  # peer_id -> {steam_id, display_name, player_node_path}

func start_host() -> void
func start_client(host_steam_id: int) -> void
func disconnect_all() -> void
func is_host() -> bool
func is_authority_for(node: Node) -> bool   # convenience used by every system
```

Internals: instantiate `SteamMultiplayerPeer`, call `create_host()` / `create_client()`, assign to `multiplayer.multiplayer_peer`. Hook `multiplayer.peer_connected`, `peer_disconnected`, `server_disconnected`, `connection_failed`.

When a peer connects (server side): server calls `_register_peer(peer_id, steam_id)` via `@rpc("authority", "reliable")` on all clients to broadcast the roster.

### `globals/authority_router.gd`
Helper used by every script: `AuthorityRouter.server_only(callable)` runs the callable only on server. `AuthorityRouter.on(node, signal_name, callable)` connects a signal only on the authority for that node. Keeps `if multiplayer.is_server()` boilerplate out of every script.

### Lobby UI
- `scenes/ui/lobby_menu.tscn` — buttons: Host, Join Friend, Start Game, Leave.
- Replace any current "press F5 → directly into World.tscn" flow: make `LobbyMenu.tscn` the new main scene (`project.godot` `run/main_scene`). World.tscn loads only after lobby start.

### Acceptance
- Two Godot instances on same machine can host + join a Steam lobby (Spacewar app id 480 works locally).
- Console prints peer ids on both sides on connect.
- Leaving lobby returns to lobby menu.

---

## Phase 2 — Player Refactor (Input → Server → Correction)

**This is the biggest single change in the project. Read fully before editing.**

### Files
- `scripts/player/player.gd` (heavy edits)
- `scenes/player/Player.tscn` (add `MultiplayerSynchronizer`, restructure node tree)
- `scripts/player/player_input.gd` (NEW — local-only)
- `scripts/player/player_remote.gd` (NEW — minimal class for non-owner players)
- `scripts/player/movement_states/state.gd` (replace `Controls.move_vector()` reads)
- `globals/controls.gd` (mark as local-only; remove direct reads from authoritative paths)
- `scenes/world/World.tscn` + spawner setup

### Step-by-step

#### 2.1 — Restructure Player scene
Current `Player.tscn` is a `CharacterBody3D` with `CameraPivot`, `MovementStateMachine`, `ActionStateMachine`, `Inventory`, `WeaponMount`, `ShieldMount`, `Hurtbox`.

New layout:
```
Player (CharacterBody3D)                    ← server-authoritative
├── MultiplayerSynchronizer (sync_config: position, rotation, velocity, hp, stamina, anim_state)
├── NetInput (Node, local-only)             ← only enabled if multiplayer.get_unique_id() == authority
├── MovementStateMachine                    ← runs on server only
├── ActionStateMachine                      ← runs on server only
├── Hurtbox (Area3D, layer Hurtbox)
├── WeaponMount / ShieldMount               ← visual + hitbox; hitbox enabled only on server
├── Inventory                               ← server-authoritative for pickups; replicated to owner only
└── LocalView (Node3D, local-only, owner peer only)
    ├── CameraPivot + SpringArm3D + Camera3D
    ├── HUD CanvasLayer
    └── PredictionGhost (visual only, for CSP debug)
```

The Player node's **multiplayer authority** is set to the owning peer's id (not the server). This means:
- The owning client predicts movement locally and pushes input to the server.
- Server runs the *real* physics for that player and replicates corrected state back via the synchronizer.
- Other clients receive replicated state and interpolate.

Use `set_multiplayer_authority(peer_id)` on the Player root in `_enter_tree()`, fed by the value set by the spawner.

> **Caveat for retrofit pragmatism:** Godot's `MultiplayerSynchronizer` defaults to "owner pushes state." That gives the *client* authority. We want **server authority over the canonical position** but with **client prediction**. The cleanest pattern in Godot 4.6 is:
> - Set authority of `Player` root to the **server (peer id 1)** for shared state replication.
> - Have a child node `NetInput` whose authority is set to the **owning client** — that node calls `@rpc("any_peer", "unreliable_ordered", "call_remote") func push_input(frame, move_vec, look_vec, buttons_bitmask)` targeted at the server.
> - The server consumes inputs, runs physics, and the parent synchronizer pushes corrected state back to all peers.

Adopt that pattern. It is the recommended path.

#### 2.2 — `player_input.gd` (NEW)
Replaces direct `Controls.move_vector()` reads inside states. Runs only on the owning client.
```gdscript
extends Node
class_name PlayerInput

@export var player_path: NodePath
var _player: CharacterBody3D
var _seq: int = 0                       # monotonic input sequence number

func _ready() -> void:
    _player = get_node(player_path)
    set_process(_player.get_multiplayer_authority() == multiplayer.get_unique_id())

func _physics_process(_dt: float) -> void:
    var move := Controls.move_vector()
    var look := _player.get_aim_yaw()
    var buttons := _pack_buttons()
    _seq += 1
    rpc_id(1, "_recv_input", _seq, move, look, buttons)
    # local prediction:
    _player.apply_input_predicted(_seq, move, look, buttons)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _recv_input(seq: int, move: Vector2, look: float, buttons: int) -> void:
    # runs on server
    _player.apply_input_authoritative(seq, move, look, buttons)
```
Pack buttons as a bitmask: bit 0 jump, bit 1 sprint, bit 2 dodge, bit 3 attack_light, bit 4 attack_heavy, bit 5 block, bit 6 interact.

#### 2.3 — `player.gd` edits
- Add fields: `last_acked_seq: int`, `pending_inputs: Array` (ring buffer of last 60 inputs for replay/correction).
- New method `apply_input_predicted(seq, move, look, buttons)` — client-side: runs movement state physics using the input, mutates `velocity` and `position` locally. Stores input in `pending_inputs` indexed by seq.
- New method `apply_input_authoritative(seq, move, look, buttons)` — server-side: runs the same physics, mutates real state. Echoes `last_acked_seq = seq` into a replicated property.
- New method `_reconcile()` — client-side: when server pushes an updated `position` along with `last_acked_seq`, snap to that, then re-apply all `pending_inputs` with `seq > last_acked_seq`. If predicted position drifted > 0.05 m from corrected, smooth-blend over 100 ms.
- Existing `_on_mouse_look` stays local-only (camera only). Look yaw is sent over the wire via input RPC; server applies it to the player rotation.
- `take_damage(amount, source)` — wrap body with `if not multiplayer.is_server(): return`. HP is server-side. Replicated via synchronizer.
- `die()`, `respawn()` — server-only. Server picks spawn anchor and replicates new position.
- `_regen_stamina()` — server-only.
- `consume_stamina()` — server-only (called from server-side state code).
- `EventBus.player_hp_changed.emit(...)` — split: server emits an RPC `notify_hp_changed(peer_id, hp, max_hp)` (`@rpc("authority", "reliable", "call_local")`) that calls `EventBus.player_hp_changed.emit(...)` on each peer.

#### 2.4 — Movement states
Files in `scripts/player/movement_states/*.gd`.

Today each state reads `Controls.move_vector()` directly inside `physics_update`. After the refactor, the **state machine runs on the server** and consumes the most recent input from the player node:

```gdscript
# state.gd
func physics_update(dt: float) -> void:
    var input := player.current_input               # set by apply_input_authoritative
    var move := input.move
    ...
```

`Controls` autoload becomes UI/menu-only: keep it for lobby and pause menu, but **forbid** authoritative paths from reading it. Add a comment at top of `controls.gd`: `# Local UI input only. Do not read from game systems — they get input via PlayerInput RPC.`

#### 2.5 — Camera
`scripts/player/player_camera.gd` stays local-only — only attached under the `LocalView` node which exists only on the owning client. No changes other than ensuring the camera scene is not instantiated for non-owner players.

#### 2.6 — Player spawn
- Remove any "Player is preplaced in World.tscn" — delete the player instance from `World.tscn`.
- Add a `MultiplayerSpawner` node to World.tscn with `spawn_path = "/root/World/Players"` and `spawn_limit = 4`, registered scene: `res://scenes/player/Player.tscn`.
- In `NetworkManager`: when a peer connects (server side), call `_spawn_player(peer_id)` which instantiates Player.tscn, calls `set_multiplayer_authority(peer_id)` on it (before adding to tree), sets its initial position from `IslandRegistry.get_mainland_placement()`, and adds it under `/root/World/Players`. MultiplayerSpawner replicates this to all clients.

### Acceptance
- Two players in lobby; both spawn; each sees their own player + the other's. WASD moves your own player, not the other's.
- Sprint/jump/dodge work for both.
- Yanking the network cable (or `multiplayer.multiplayer_peer = null`) on the host visibly freezes the client's view of the host player and vice versa.
- Local prediction is visible (no input lag on own movement under 100 ms simulated latency — test with Godot's `Multiplayer → Debug` simulated lag).

---

## Phase 3 — Combat Refactor (server-authoritative damage)

### Files
- `scripts/combat/sword.gd`
- `scripts/combat/hitbox.gd`
- `scripts/combat/hurtbox.gd`
- `scripts/combat/combat_resolver.gd`
- `scripts/player/action_states/attack.gd` (and block, dodge)
- NEW: `scripts/combat/rewind_buffer.gd` — server-side snapshot of player/enemy positions for lag comp

### 3.1 — Hitbox / Hurtbox
- `hitbox.gd` line 12 currently connects `area_entered` and applies damage locally. Wrap entire body in `if not multiplayer.is_server(): return`. Hitboxes only exist meaningfully on the server. On clients they exist as visual placeholders but never trigger damage.
- The hitbox's `monitoring` toggle should also be server-only. Clients can still play the swing animation locally (visual prediction), but the *real* hit decision is server-side.
- Set the hitbox's collision layer to layer 2 only on the server; on clients, hitbox layer = 0 to be safe.

### 3.2 — `sword.gd` (`swing()` at line 23)
Split into two methods:
- `predict_swing()` — local visual: plays animation on the wielder's client immediately for responsiveness. No damage. Triggered when player presses attack_light.
- `swing_authoritative()` — server: runs the swing timer, enables hitbox at `WINDUP_DURATION`, disables after STRIKE window. This is the only path that can apply damage.

The attack state (`scripts/player/action_states/attack.gd`) detects button via the input RPC; on server side it calls `swing_authoritative()`. On owning client, also call `predict_swing()` for instant visual.

### 3.3 — Lag-compensated hit detection
Create `scripts/combat/rewind_buffer.gd`:
```gdscript
extends Node
class_name RewindBuffer

# Server-only. Snapshots transforms of all networked combatants each physics tick.

const HISTORY_TICKS := 30     # ~500 ms at 60 Hz
var _snapshots: Array = []    # ring buffer of {tick, dict[node_path -> Transform3D]}

func record(tick: int) -> void
func rewind(tick: int, target_paths: PackedStringArray) -> Dictionary
func with_rewound(target_paths: PackedStringArray, target_tick: int, body: Callable) -> void
```
Autoload as `RewindBuffer` (add to `project.godot` autoload list, after `NetworkManager`).

In `hitbox.gd`, when checking damage on server, briefly rewind the *target's* transform to the attacker's view-tick (attacker tick = `current_tick - estimated_ping_in_ticks`) before running the area overlap query. Use `with_rewound` to scope the temporary transform swap. Restore after.

For a melee game with 1–4 players over Steam relay this can be simplified: rewind only the target hurtbox, not the attacker's hitbox. Tolerance is generous because we're host-authoritative and ping is typically <80 ms.

### 3.4 — `combat_resolver.gd`
Add a `server_only` guard. Damage multiplier reads `SkillManager.get_level(skill_id)` — that lives on the server's authoritative `SkillManager`. Skill levels for the *attacker* (a player) need to be queried from the per-peer profile mirror on the server (see Phase 8 for the profile mirror).

### 3.5 — Damage flow summary
1. Client presses attack → input RPC fires.
2. Server's attack state runs; sword animates; hitbox enables at WINDUP.
3. Hitbox `area_entered` (server only) → calls `CombatResolver.resolve()` (server only) → calls `target.take_damage()` (server only).
4. Target HP mutates → MultiplayerSynchronizer replicates the new HP value to all peers.
5. Server fires `@rpc("authority","reliable","call_local") notify_damage(target_path, amount, source_path)` to play hit VFX/SFX on all peers.
6. Death → server runs `die()` → emits `enemy_killed` RPC to all peers → server runs `_drop_loot()` → loot spawned via MultiplayerSpawner.

### 3.6 — Block / parry / stagger
- `is_blocking`, `is_parrying` are server-authoritative state. Client requests via input bitmask. Server toggles flags.
- `player_parried` signal → wrap in RPC like damage.

### Acceptance
- Host player can kill enemy near guest player; both clients see HP bar drop in sync.
- Guest player can kill enemy; host's screen sees the death.
- Two-player friendly-fire test (if enabled): hitting host as guest produces damage server-side and replicates.
- Disconnect mid-swing on guest: host's authoritative simulation does not crash; sword animation halts but world continues.

---

## Phase 4 — Enemy AI Refactor

### Files
- `scripts/enemies/enemy.gd`
- `scripts/enemies/enemy_states/movement_state/*.gd` (idle, patrol, chase, flee, sense, return)
- `scripts/enemies/enemy_states/action_state/*.gd` (idle, attack, stagger)
- `scenes/enemies/Husk.tscn`, `TargetDummy.tscn`

### 4.1 — Server-only logic
At the top of `enemy.gd` `_ready()`:
```gdscript
if not multiplayer.is_server():
    movementSM.set_physics_process(false)
    actionSM.set_physics_process(false)
    set_physics_process(false)
    # keep hurtbox active so server-side hitboxes can still report visually
    # but disable our own attack hitbox monitoring
    $AttackHitbox.monitoring = false
    return
```
This is the single most important line in the enemy file. Clients become **dumb interpolating ghosts** for enemies.

### 4.2 — Replicated state
Add a `MultiplayerSynchronizer` child to `Husk.tscn` and `TargetDummy.tscn`:
- Replicate: `global_transform.origin`, `global_transform.basis` (or just rotation_y), `hp`, current movement state name, current action state name, current animation pose (an enum or string).
- Replication interval: 50 ms (20 Hz). Use `replication_interval = 0.05` and `delta_interval = 0.05`.
- Set the synchronizer's `replication_config.visibility_update_mode = ON_DEMAND` and write `visibility_filter` so an enemy only replicates to clients whose player is within ~150 m (interest management). Implement via `MultiplayerSynchronizer.set_visibility_for(peer_id, bool)` and a per-tick recompute in WorldStream.

### 4.3 — Attack hitbox
`scripts/enemies/enemy_states/action_state/attack.gd` lines 60–71: `_on_hitbox_entered()` → wrap in server-only guard. Damage still calls `target.take_damage()` which is also server-only.

### 4.4 — Spawning
Currently enemies are placed by island Near-tier scenes. After retrofit, the **server** instantiates Near-tier and adds enemies via `MultiplayerSpawner`. Add a `MultiplayerSpawner` at `World/Enemies` with the enemy scenes registered. Move enemy spawn calls into `WorldStream._load_near` and gate them with `if multiplayer.is_server()`.

### 4.5 — Loot drop
`enemy.gd` lines 71–77 `_drop_loot()` — wrap in server-only. Spawn `ItemPickup` via MultiplayerSpawner (`World/Pickups`).

### Acceptance
- Single enemy aggros on whichever player is closest; both clients see the same chase target, same animation, same hp.
- Killing enemy on either client drops loot visible to both.
- Disconnect a client mid-fight: enemy continues attacking the remaining player(s) seamlessly.

---

## Phase 5 — Boats Refactor

### Files
- `scripts/ships/boat.gd`
- `scenes/ships/Boat.tscn`
- `globals/boat_manager.gd`

### 5.1 — Authority
Boats are `RigidBody3D`. Network-sync RigidBody3D is tricky; use the standard pattern:
- Server runs the rigid body physics. Authority = peer 1.
- Replicate `global_transform`, `linear_velocity`, `angular_velocity` via `MultiplayerSynchronizer` at 20 Hz.
- On clients, set `freeze = true` and `freeze_mode = FREEZE_MODE_KINEMATIC`, then interpolate transform from the synchronizer manually (write a small `_process` lerp targeting the last replicated transform).

### 5.2 — Mount / dismount
`_on_interact` (lines 55–61) → server-only. Input "interact" comes through the player input RPC. The mounting client's player parents to `_deck_spawn`. To make this work over the network:
- On server: reparent player under boat (call `boat._mount(player)`).
- Reparenting under a replicated node may break the spawner contract. Safer alternative: **don't reparent** — instead, every physics tick on the server set `player.global_transform = boat._deck_spawn.global_transform`. The original code (line 130) already does this.
- Set `player.on_boat = true` server-side; replicate via synchronizer or via a property in PlayerState.
- The mounting client's local camera switches via a local-only listener on `player.on_boat` (signal `player.on_boat_changed`).

### 5.3 — Cannons
`fire_cannon` input → server validates, spawns projectile via MultiplayerSpawner, projectile physics runs on server, hits resolve server-side.

### 5.4 — Multiple players on one boat
Allow up to 4 players mounted simultaneously. Add `_mounted_players: Array[Player]` to boat; mount/dismount add/remove. Each mounted player snaps to a different deck slot (`DeckSpawn1`, `DeckSpawn2`, etc.). Existing single `_deck_spawn` becomes `_deck_spawns: Array[Marker3D]`.

### 5.5 — BoatManager save
Today BoatManager saves boat position/velocity. Server-only saves. Wrap `_save`/`_load` paths with `if not multiplayer.is_server(): return`.

### Acceptance
- Host spawns boat. Guest sees it.
- Both players board it. Host steers; boat moves; guest's view follows correctly.
- Guest steers (or host transfers control via interact): same.
- Save and reload (host): boat returns to last position.

---

## Phase 6 — World Streaming Refactor

### Files
- `globals/world_stream.gd`
- `globals/island_registry.gd` (minor)

### 6.1 — Multi-player streaming
`WorldStream._update_tiers_and_biome()` currently checks one `_player`. Change to:
- Maintain `_players: Array[Player]` (registered via `set_player`, now `register_player(p)` / `unregister_player(p)`).
- For each island placement, compute the *minimum distance* to any registered player.
- Apply tier thresholds against that min distance. An island is in Near tier if *any* player is within 60 m.
- Run streaming **only on the server**: `if not multiplayer.is_server(): set_process(false); return` in `_ready()` for clients. Clients receive replicated Near-tier nodes via MultiplayerSpawner and replicated enemies/pickups within them. Far/mid visual meshes load on all peers independently from local resources (they're identical static content).

Implementation detail: Far/mid tiers contain only visual + collider data that doesn't need network sync. Keep them loading locally on every peer (no server gating). **Only Near-tier streaming (enemies, pickups, deltas) is server-gated and replicated.**

### 6.2 — DeltaRoot
`IslandDeltaStore` is the persistent delta for an island (e.g. picked-up items, killed enemies). Server-only. Replicated to clients on near-tier load via MultiplayerSpawner of pre-existing nodes within DeltaRoot.

### 6.3 — Biome enter signal
`biome_entered` is per-player. Each client computes its own biome from its local player position (no server round-trip needed for cosmetic biome detection). Keep this client-local; do not network it.

### Acceptance
- Two players on different islands: each island's near tier loaded (both islands populated server-side).
- Players on same island: near tier loaded once, both clients see same enemy positions.
- Player crosses biome boundary: only that player's HUD biome tag updates; the other player's HUD does not.

---

## Phase 7 — Inventory & Item Pickups

### Files
- `scripts/inventory/inventory.gd`
- `scripts/items/item_pickup.gd`

### 7.1 — Inventory ownership
Inventory is **per-player, server-authoritative**. The server owns the canonical inventory for each player. The owning client gets the inventory replicated to them via `MultiplayerSynchronizer.visibility_filter` so only that peer sees their own slots.

### 7.2 — Pickup flow
`item_pickup.gd` `_process` chases player and on collision calls `player.take_pickup(item_id, count)`.
- Wrap chase logic and collision in server-only.
- On server: `take_pickup()` → `inventory.add()` (server-side) → free the pickup. The free is replicated by MultiplayerSpawner removing the node from all clients.
- Fire `EventBus.item_picked_up` only on the owning client via `@rpc("authority","reliable") notify_pickup(peer_id, item_id, count)` → on the matching peer, emit the signal.

### 7.3 — Pickup spring animation
The spring/chase animation is cosmetic — can run client-side for smoothness, but the *authoritative position* and the *which-player-collected* decision are server-side. Either:
- Replicate position via synchronizer and let server own everything (simpler), OR
- Let each client run the chase animation locally for its own player, server just validates pickup eligibility. (More responsive but more code.)

Choose option (1) for the retrofit. Revisit if pickup feel is laggy.

### Acceptance
- Enemy drops loot. Closer player picks up. Only that player's inventory increments. Other player's HUD does not show pickup. Pickup disappears for both.

---

## Phase 8 — Save System Split

### Files
- `globals/save_system.gd` (refactor)
- NEW: `globals/profile_save.gd` (per-player local save)

### 8.1 — Two-tier save
- **World save** (`user://save.dat`, host-only): world seed, time-of-day, island deltas, boat positions, discovery log (host-side world unlocks). Existing SaveSystem handles this. Add a top guard: `func save(): if not NetworkManager.is_host(): return`. Same for `load_or_init()`.
- **Profile save** (`user://profile.dat`, each peer locally): player skills, inventory, cosmetics. New autoload `ProfileSave` mirrors the existing duck-typed `save_data()` / `load_data()` pattern but for per-player nodes.

### 8.2 — Skill / inventory persistence
On guest connect (server side):
1. Server requests profile from guest: `@rpc("authority","reliable") request_profile(peer_id)`.
2. Guest's client reads `user://profile.dat` and replies: `@rpc("any_peer","reliable") send_profile(skills_dict, inventory_array)`.
3. Server loads those into the spawned Player's SkillManager mirror and Inventory.

SkillManager today is a global autoload. After retrofit it must hold **per-peer skill state on the server**: change `SkillManager.skills` from `Dictionary` to `Dictionary[int, Dictionary]` keyed by peer id. Update `add_xp(skill_id, amount)` to `add_xp(peer_id, skill_id, amount)`. Helper `add_xp_local(skill_id, amount)` resolves peer_id automatically via the caller's player node.

On guest disconnect or session end:
1. Server pushes profile back: `@rpc("authority","reliable") receive_profile(skills, inventory)`.
2. Guest writes to `user://profile.dat`.

For the host, profile and world save coexist on the same machine.

### 8.3 — Migration
Bump save schema version. Old single-player saves load into host's combined world+profile and split on first save.

### Acceptance
- Host saves and reloads; world state intact.
- Guest joins, earns XP, leaves, rejoins (new session, different host): guest's XP persisted via own profile.
- Two guests have independent inventories.

---

## Phase 9 — EventBus, UI, Audio Sync

### Files
- `globals/event_bus.gd` (unchanged structure — see rule 8)
- `scripts/ui/*.gd` (wire all HUD elements to local EventBus only)
- `globals/audio_director.gd`

### 9.1 — Pattern for "shared" events
For any event that today fires on the single client and updates UI, define an RPC twin on the source-of-truth node. Example for `enemy_killed`:
```gdscript
# enemy.gd, server side:
func _die(source):
    EventBus.enemy_killed.emit(def.id, source)   # server's local signal
    rpc("_notify_enemy_killed", def.id, source.get_path() if source else NodePath())

@rpc("authority","reliable","call_remote")
func _notify_enemy_killed(enemy_id, source_path):
    var source = get_node_or_null(source_path)
    EventBus.enemy_killed.emit(enemy_id, source)
```

Repeat for: `damage_dealt`, `player_hp_changed`, `player_stamina_changed`, `player_died`, `player_respawned`, `player_parried`, `skill_xp_gained`, `skill_leveled`, `station_discovered`, `boss_defeated`, `item_picked_up`, `island_loaded/unloaded` (only if UI needs them).

Keep purely local signals as-is: `time_phase_changed` (each peer computes time independently from a replicated `game_minutes`), `biome_entered` (per-player local), `world_loaded`.

### 9.2 — TimeOfDay sync
TimeOfDay autoload: server runs the clock. Replicate `game_minutes` and `phase` via a small `MultiplayerSynchronizer` on a `TimeSync` node in `World.tscn`. Clients read those replicated values and re-emit `time_phase_changed` on phase transitions locally. Don't tick `game_minutes` on clients.

### 9.3 — AudioDirector
Each peer plays its own audio. Combat music stinger triggered by `damage_dealt` — since damage RPC fires on all peers, this works naturally. Just ensure music transitions don't double-fire (guard with "is this me / is this near me?").

### Acceptance
- Both players' HUDs show their own HP/stamina correctly.
- Skill XP popup appears only on the player who earned XP.
- Time of day matches on both clients to within 1 second.

---

## Phase 10 — Testing & Hardening

### 10.1 — Automated tests (extend `tests/`)
- `test_network_manager.gd` — host/client start/stop lifecycle (mock SteamMultiplayerPeer with `OfflineMultiplayerPeer` for tests).
- `test_authority_router.gd` — `is_authority_for` returns correct values.
- `test_player_prediction.gd` — given a sequence of inputs + a delayed server correction, `_reconcile` produces the right final position.
- `test_rewind_buffer.gd` — record N snapshots, rewind to a tick, verify transforms restored.

Run via GUT (the project already uses it).

### 10.2 — Manual test matrix
| Scenario | Expected |
|---|---|
| Host alone | Game plays identically to pre-retrofit single-player. |
| Host + 1 guest, idle 5 min | No drift; both players see each other still. |
| Host + 3 guests, combat | All HP/positions sync; no rubber-banding worse than 200 ms ping. |
| Guest disconnects mid-fight | Enemy retargets to remaining player; no crash. |
| Guest rejoins | Re-spawned at mainland; profile reloaded; world state intact. |
| Host quits | Lobby closes; all guests return to lobby menu. |
| 100 ms simulated lag (Godot debug) | Movement still feels responsive on guest. |
| Two players hit same enemy simultaneously | Damage applied in arrival order on server; kill credit to the killing blow. |

### 10.3 — Soak test
Run a 30-minute 4-player session with combat, boating, island streaming. Watch for:
- Memory leaks (orphan synchronizers / spawners on disconnect).
- Replication storms (too many spawned items / pickups).
- Save corruption.

---

## Critical Files Map (for the executing agent)

| File | Phase | Change type |
|---|---|---|
| `project.godot` | 0 | autoloads, layers, main_scene |
| `globals/network_manager.gd` | 1 | NEW |
| `globals/steam_lobby.gd` | 1 | NEW |
| `globals/authority_router.gd` | 1 | NEW |
| `globals/world_stream.gd` | 6 | server-only gating, multi-player tracking |
| `globals/time_of_day.gd` | 9 | server-only tick + replicate |
| `globals/save_system.gd` | 8 | host-only world save |
| `globals/profile_save.gd` | 8 | NEW |
| `globals/skill_manager.gd` | 8 | per-peer keying |
| `globals/event_bus.gd` | 9 | no structural change; clarify local-only |
| `globals/boat_manager.gd` | 5 | server-only save |
| `scripts/player/player.gd` | 2 | apply_input_*, reconcile, server-only damage/respawn |
| `scripts/player/player_input.gd` | 2 | NEW |
| `scripts/player/player_camera.gd` | 2 | local-only mounting |
| `scripts/player/movement_states/*.gd` | 2 | read input from player.current_input |
| `scripts/player/action_states/attack.gd` | 3 | predict + authoritative swing split |
| `scripts/combat/sword.gd` | 3 | predict_swing / swing_authoritative |
| `scripts/combat/hitbox.gd` | 3 | server-only |
| `scripts/combat/hurtbox.gd` | 3 | (passive, no change needed) |
| `scripts/combat/combat_resolver.gd` | 3 | server-only; per-peer skill lookup |
| `scripts/combat/rewind_buffer.gd` | 3 | NEW |
| `scripts/enemies/enemy.gd` | 4 | client = ghost; server-only AI |
| `scripts/enemies/enemy_states/**/*.gd` | 4 | server-only logic |
| `scripts/ships/boat.gd` | 5 | server-physics + replicate |
| `scripts/inventory/inventory.gd` | 7 | server-authoritative + per-peer visibility |
| `scripts/items/item_pickup.gd` | 7 | server-only logic |
| `scenes/world/World.tscn` | 1, 2, 4, 7 | add MultiplayerSpawner for Players/Enemies/Pickups, add TimeSync |
| `scenes/player/Player.tscn` | 2 | add MultiplayerSynchronizer, NetInput, LocalView |
| `scenes/enemies/Husk.tscn`, `TargetDummy.tscn` | 4 | add MultiplayerSynchronizer |
| `scenes/ships/Boat.tscn` | 5 | add MultiplayerSynchronizer; multiple deck spawns |
| `scenes/ui/lobby_menu.tscn` (+ .gd) | 1 | NEW |
| `tests/test_*.gd` | 10 | NEW network tests |

---

## Verification (end-to-end)

After every phase, run:
1. `Project → Tools → GUT → Run All Tests` — no regressions.
2. Launch two instances (`Godot → Debug → Run Multiple Instances → 2`), one hosts, one joins via the test lobby.
3. Walk through the phase's acceptance criteria checklist.

After the full retrofit, the canonical smoke test is:
1. Host launches game → lobby menu → host.
2. Three guests join via Steam friend invite.
3. All four spawn on mainland.
4. They sail a boat together to a forest island.
5. They fight an enemy spawn. Two die. The survivors loot drops; pickups land in their inventories.
6. Host quits and reloads. The world state (killed enemies, picked-up items, boat position) persists. Guests reconnect and see the new world.
7. Each guest's `user://profile.dat` retains the skills/inventory they earned across sessions.

If all of that works, the retrofit is done.

---

## Notes for the executing agent (Claude Code or lower)

- **Never skip the `is_server()` / `is_authority_for()` guard.** When in doubt, add it. False positives (extra guard) cost nothing; false negatives (missing guard) cause desync.
- **Don't use Godot's default unannotated `@rpc`.** Always specify mode + transfer reliability + call_local explicitly. This is a code-review checkpoint.
- **Phases 2 and 3 (player + combat) are the riskiest.** Do them on a branch; verify before moving on.
- **Don't try to "network the EventBus."** It is local-only by design. Use explicit RPCs whose handlers re-emit the local signal — Rule 8 and the pattern in §9.1.
- **GodotSteam SteamMultiplayerPeer can be mocked with `OfflineMultiplayerPeer` for unit tests** — don't require Steam to be running for CI.
- **When a scene must spawn on all peers, route it through a MultiplayerSpawner — never `add_child` it on the server.** This is the most common networking bug in Godot 4.
- **Interest management (§4.2 visibility filters) is optional for 4 players but trivially worth it — keep replication tight from day one.**
