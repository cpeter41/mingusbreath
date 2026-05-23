extends Node
# Single source of truth for peer / multiplayer state.
#
# Phase 0: stub that recognizes --offline / --host / --join cmdline args and uses
# ENetMultiplayerPeer for local testing. Phase 1 adds the Steam transport path.
#
# Authority model is host-authoritative listen-server. See MULTIPLAYER_RETROFIT_PLAN.md.

signal peer_player_joined(peer_id: int, steam_id: int)
signal peer_player_left(peer_id: int)
signal network_ready
signal mode_changed(is_host: bool)
signal roster_changed                            # peers dict mutated; lobby UI refreshes
signal world_loaded                              # host has loaded world scene

enum Mode { OFFLINE, HOST, CLIENT }

const ENET_PORT := 7777
const ENET_MAX_CLIENTS := 4
const WORLD_SCENE_PATH := "res://scenes/world/World.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player/Player.tscn"
const LOBBY_SCENE_PATH := "res://scenes/ui/LobbyMenu.tscn"
const HUSK_SCENE := "res://scenes/enemies/Husk.tscn"

var mode: int = Mode.OFFLINE
var local_peer_id := 1
var peers: Dictionary = {}  # peer_id -> {steam_id, display_name}

var _use_enet_fallback: bool = false
var _enet_host_ip: String = "127.0.0.1"
var _world_loaded: bool = false
var _world_root: Node = null  # set by WorldRoot._ready after scene swap

# Join-handshake state (guest side).
var _peer_connected: bool = false        # true once connected_to_server fires
var _world_built_pending: bool = false   # World built, _guest_world_ready not yet sent


func _ready() -> void:
	print("[NetworkManager] ready (mode=OFFLINE)")
	_parse_cmdline()
	# Auth handshake: gates peer_connected (and thus all scene replication) until
	# a mid-session joiner has built its World tree. Without this, the host's
	# MultiplayerSpawners replicate existing content before the guest's World
	# exists, permanently poisoning the spawner path cache. See _auth_callback.
	multiplayer.auth_callback = _auth_callback
	multiplayer.auth_timeout = 20.0
	multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_peer_authentication_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

	# Auto-start based on cmdline so two Godot instances can be wired up via run args.
	if _use_enet_fallback:
		var args := OS.get_cmdline_args()
		if "--host" in args:
			# Defer so autoloads finish ready before scene change.
			call_deferred("_cmdline_autostart_host")
		elif "--join" in args:
			call_deferred("_cmdline_autostart_client")


## Cmdline auto-start skips the lobby UI, so no slot was picked. Use (creating
## if needed) a "default" world + character so the dev path still boots.
func _ensure_default_slots(need_world: bool) -> void:
	if need_world and SaveSystem.current_world == "":
		var worlds := SaveSystem.list_worlds()
		SaveSystem.set_world(worlds[0] if worlds.size() > 0 else SaveSystem.create_world("default"))
	if ProfileSave.current_character == "":
		var chars := ProfileSave.list_characters()
		ProfileSave.set_character(chars[0] if chars.size() > 0 else ProfileSave.create_character("default"))


func _cmdline_autostart_host() -> void:
	_ensure_default_slots(true)
	start_host()
	# Give a moment for any --join client on the same machine to connect, then load world.
	await get_tree().create_timer(2.0).timeout
	load_world()


func _cmdline_autostart_client() -> void:
	_ensure_default_slots(false)
	start_client(_enet_host_ip)
	# Wait for host to issue _remote_load_world RPC.


func _parse_cmdline() -> void:
	var args := OS.get_cmdline_args()
	_use_enet_fallback = "--offline" in args
	var join_idx := args.find("--join")
	if join_idx >= 0 and join_idx + 1 < args.size():
		_enet_host_ip = args[join_idx + 1]
	if _use_enet_fallback:
		print("[NetworkManager] --offline flag detected: will use ENet transport")


func is_host() -> bool:
	return mode == Mode.HOST


func is_offline() -> bool:
	return mode == Mode.OFFLINE


func is_authority_for(node: Node) -> bool:
	if mode == Mode.OFFLINE:
		return true
	return node.get_multiplayer_authority() == multiplayer.get_unique_id()


func start_host() -> void:
	if _use_enet_fallback or not SteamLobby.available:
		_start_host_enet()
	else:
		_start_host_steam()
	mode = Mode.HOST
	local_peer_id = 1
	mode_changed.emit(true)
	network_ready.emit()


func start_client(host_addr: Variant) -> void:
	if _use_enet_fallback or not SteamLobby.available:
		_start_client_enet(str(host_addr))
	else:
		_start_client_steam(int(host_addr))
	mode = Mode.CLIENT
	mode_changed.emit(false)


func disconnect_all() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	# Restore the offline peer (Godot's SceneTree default) rather than leaving it
	# null. A null peer makes multiplayer.is_server()/get_unique_id() push an
	# error on every call, which breaks solo play on the next world load.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	peers.clear()
	_peer_connected = false
	_world_built_pending = false
	_world_loaded = false
	print("[NetworkManager] disconnected, back to OFFLINE")


## Tears down the current session and returns to a fresh lobby. Used by the
## pause menu's Save & Quit and by guests when the host's server peer closes.
func return_to_lobby() -> void:
	get_tree().paused = false
	Controls.input_blocked = false
	Controls.release_mouse()
	disconnect_all()
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


# ── Join handshake (auth phase) ──────────────────────────────────
## Fires on both ends the instant the transport connects, before peer_connected.
## The host tells the joining guest whether a world is already running; the
## guest acts on that in _auth_callback.
func _on_peer_authenticating(peer_id: int) -> void:
	if multiplayer.is_server():
		multiplayer.send_auth(peer_id, PackedByteArray([1 if _world_loaded else 0]))
		# Host needs nothing from the guest — accept immediately. The connection
		# still won't complete until the guest also completes (after it has its
		# World built), which is the barrier we want.
		multiplayer.complete_auth(peer_id)
	# Guest: wait for the host's payload in _auth_callback.


## Receives the peer's auth payload. On the guest, the host's payload says
## whether to build the World now (mid-session join) so the guest's spawners
## exist before any replication arrives.
func _auth_callback(peer_id: int, data: PackedByteArray) -> void:
	if multiplayer.is_server():
		return  # guests send no payload; host already completed
	var host_in_world := data.size() > 0 and data[0] == 1
	if host_in_world and not (get_tree().current_scene is WorldRoot):
		_world_loaded = true
		world_loaded.emit()
		_change_to_world_scene()  # builds the World tree synchronously
	multiplayer.complete_auth(peer_id)


func _on_peer_authentication_failed(peer_id: int) -> void:
	push_warning("[NetworkManager] peer authentication failed: %d" % peer_id)


## Guest-side: signal the host our World tree is built. Gated so the RPC only
## fires once the peer connection is actually complete — for a mid-session join
## the World is built during the auth phase, before connected_to_server.
func _notify_guest_world_ready() -> void:
	if _peer_connected:
		_guest_world_ready.rpc_id(1)
	else:
		_world_built_pending = true


func _start_host_enet() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(ENET_PORT, ENET_MAX_CLIENTS)
	if err != OK:
		push_error("[NetworkManager] ENet host create_server failed: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] ENet host listening on :%d" % ENET_PORT)


func _start_client_enet(host_ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_ip, ENET_PORT)
	if err != OK:
		push_error("[NetworkManager] ENet client create_client(%s:%d) failed: %s" % [host_ip, ENET_PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] ENet client connecting to %s:%d" % [host_ip, ENET_PORT])


func _start_host_steam() -> void:
	# SteamMultiplayerPeer is registered by the GodotSteam GDExtension.
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_host(0)  # port arg ignored on Steam transport
	if err != OK:
		push_error("[NetworkManager] Steam host create_host failed: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Steam host ready (steam_id=%d)" % SteamLobby.steam_id)


func _start_client_steam(host_steam_id: int) -> void:
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_client(host_steam_id, 0)
	if err != OK:
		push_error("[NetworkManager] Steam client create_client(%d) failed: %s" % [host_steam_id, err])
		return
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Steam client connecting to host steam_id=%d" % host_steam_id)


func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] peer_connected: %d" % peer_id)
	if multiplayer.is_server():
		var display := "Peer_%d" % peer_id
		var steam_id := 0
		# If Steam transport, look up steam_id from the peer's identity.
		peers[peer_id] = {"steam_id": steam_id, "display_name": display}
		peer_player_joined.emit(peer_id, steam_id)
		# Broadcast full roster to all peers so guest UIs can render it.
		rpc("_sync_roster", peers)
		# If we've already entered the world, push the new guest into it too.
		# Spawn is deferred to _guest_world_ready so the player only replicates
		# once the guest's scene tree (and MultiplayerSpawner) is actually ready.
		if _world_loaded:
			rpc_id(peer_id, "_remote_load_world")


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] peer_disconnected: %d" % peer_id)
	if multiplayer.is_server():
		# Record this player's last position into the world save before their
		# node is freed, then despawn it.
		_record_player_position(peer_id)
		_despawn_player(peer_id)
	peers.erase(peer_id)
	peer_player_left.emit(peer_id)
	roster_changed.emit()
	if multiplayer.is_server():
		rpc("_sync_roster", peers)


## Stable cross-session id for a peer. Keyed by the player's chosen character
## slot name — stable across sessions and ENet peer-id reassignment. Falls back
## to peer id only if the character is unknown.
func get_stable_id(peer_id: int) -> String:
	if peer_id == multiplayer.get_unique_id():
		if ProfileSave.current_character != "":
			return "char_" + ProfileSave.current_character
	elif peers.has(peer_id):
		var c: String = peers[peer_id].get("character", "")
		if c != "":
			return "char_" + c
	return "peer_%d" % peer_id


## Guest tells the host which character slot it is using, so the host can key
## that player's saved position by a stable name.
func _on_connected_to_server() -> void:
	_peer_connected = true
	_register_character.rpc_id(1, ProfileSave.current_character, ProfileSave.current_class())
	# A mid-session joiner built its World during the auth phase, before this
	# fired — so the _guest_world_ready RPC was deferred. Send it now.
	if _world_built_pending:
		_world_built_pending = false
		_guest_world_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func _register_character(char_name: String, class_id: StringName = ProfileSave.DEFAULT_CLASS_ID) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		peers[sender] = {"steam_id": 0, "display_name": "Peer_%d" % sender}
	peers[sender]["character"] = char_name
	peers[sender]["class"] = class_id


## Class id for a peer, resolved consistently for host and guests:
## - host (and OFFLINE solo) reads its own ProfileSave;
## - guests come from peers[peer_id]["class"], populated by _register_character.
func _class_for_peer(peer_id: int) -> StringName:
	if peer_id == multiplayer.get_unique_id():
		return ProfileSave.current_class()
	var rec: Dictionary = peers.get(peer_id, {})
	return StringName(rec.get("class", ProfileSave.DEFAULT_CLASS_ID))


func _player_node(peer_id: int) -> Node:
	if _world_root == null:
		return null
	var players := _world_root.get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null("Player_%d" % peer_id)


func _record_player_position(peer_id: int) -> void:
	var pnode := _player_node(peer_id)
	if pnode == null:
		return
	PlayerStore.record(get_stable_id(peer_id), pnode.global_position, pnode.rotation.y)


func _despawn_player(peer_id: int) -> void:
	var pnode := _player_node(peer_id)
	if pnode != null:
		pnode.queue_free()


## Snapshot every connected player's position into PlayerStore. Called by the
## host before autosave and on world exit.
func record_all_player_positions() -> void:
	if not multiplayer.is_server() or _world_root == null:
		return
	var players := _world_root.get_node_or_null("Players")
	if players == null:
		return
	for child in players.get_children():
		# During a scene-change teardown the player nodes leave the tree before
		# WorldRoot._exit_tree runs — their transforms are then unreadable. Skip
		# them; Save & Quit already recorded positions via _do_save() in-world.
		if not (child is Node3D) or not child.is_inside_tree():
			continue
		var parts := String(child.name).split("_")
		if parts.size() == 2 and parts[0] == "Player":
			var pid := int(parts[1])
			PlayerStore.record(get_stable_id(pid), child.global_position, child.rotation.y)


func _on_server_disconnected() -> void:
	push_warning("[NetworkManager] server disconnected")
	# In a world (host quit / lost) — kick this guest back to its own lobby.
	# Still in the lobby (host left pre-start) — just drop the connection.
	if get_tree().current_scene is WorldRoot:
		return_to_lobby()
	else:
		disconnect_all()


func _on_connection_failed() -> void:
	push_warning("[NetworkManager] connection failed")
	disconnect_all()


## Host enters the world. Replicates the scene swap to all connected guests.
func load_world() -> void:
	if mode != Mode.HOST and mode != Mode.OFFLINE:
		push_warning("[NetworkManager] load_world called by non-host")
		return
	_world_loaded = true
	world_loaded.emit()
	if mode == Mode.HOST:
		rpc("_remote_load_world")
	_change_to_world_scene()


@rpc("authority", "reliable", "call_remote")
func _remote_load_world() -> void:
	# A mid-session joiner already built its World during the auth handshake.
	if get_tree().current_scene is WorldRoot:
		_world_loaded = true
		return
	_world_loaded = true
	world_loaded.emit()
	_change_to_world_scene()


@rpc("authority", "reliable", "call_remote")
func _sync_roster(new_roster: Dictionary) -> void:
	peers = new_roster
	roster_changed.emit()


## Guest calls this from WorldRoot._ready() once its scene tree is fully set up
## so the MultiplayerSpawner can receive the replicated Player spawn immediately.
## Replaces the old fixed 1-second timer in _on_peer_connected.
@rpc("any_peer", "reliable")
func _guest_world_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peers.has(peer_id) and _world_loaded:
		_spawn_player_for_peer(peer_id)


## Networked damage event. The attacker's peer calls this; it re-emits
## EventBus.damage_dealt on every peer (call_local covers the attacker) so
## HUDs / audio / VFX on all clients see the hit. Nodes are passed as paths
## since Node references can't cross the wire.
func broadcast_damage(attacker: Node, target: Node, weapon_id: StringName, skill_id: StringName, amount: float) -> void:
	var ap: NodePath = attacker.get_path() if attacker != null else NodePath()
	var tp: NodePath = target.get_path() if target != null else NodePath()
	if multiplayer.multiplayer_peer == null:
		# Offline — no peers to notify; emit directly.
		EventBus.damage_dealt.emit(attacker, target, weapon_id, skill_id, amount)
		return
	_damage_event.rpc(ap, tp, weapon_id, skill_id, amount)


@rpc("any_peer", "reliable", "call_local")
func _damage_event(attacker_path: NodePath, target_path: NodePath, weapon_id: StringName, skill_id: StringName, amount: float) -> void:
	var attacker := get_node_or_null(attacker_path)
	var target := get_node_or_null(target_path)
	EventBus.damage_dealt.emit(attacker, target, weapon_id, skill_id, amount)


## Broadcast a chat message to every connected peer. call_local so the sender
## also sees their own message without a special-case path.
func broadcast_chat(sender_name: String, text: String) -> void:
	if multiplayer.multiplayer_peer == null:
		EventBus.chat_message_received.emit(sender_name, text)
		return
	_chat_event.rpc(sender_name, text)


@rpc("any_peer", "reliable", "call_local")
func _chat_event(sender_name: String, text: String) -> void:
	EventBus.chat_message_received.emit(sender_name, text)


## Networked enemy death. Re-emits EventBus.enemy_killed on every peer so skill
## XP / UI hooks fire everywhere. Twin of broadcast_damage.
func broadcast_enemy_killed(enemy_id: StringName, killer: Node) -> void:
	var kp: NodePath = killer.get_path() if killer != null else NodePath()
	if multiplayer.multiplayer_peer == null:
		EventBus.enemy_killed.emit(enemy_id, killer)
		return
	_enemy_killed_event.rpc(enemy_id, kp)


@rpc("any_peer", "reliable", "call_local")
func _enemy_killed_event(enemy_id: StringName, killer_path: NodePath) -> void:
	EventBus.enemy_killed.emit(enemy_id, get_node_or_null(killer_path))


## Networked parry. Re-emits EventBus.player_parried on every peer so the
## attacking enemy (which lives on the server) hears a guest's parry.
func broadcast_parried(attacker: Node) -> void:
	var ap: NodePath = attacker.get_path() if attacker != null else NodePath()
	if multiplayer.multiplayer_peer == null:
		EventBus.player_parried.emit(attacker)
		return
	_parried_event.rpc(ap)


@rpc("any_peer", "reliable", "call_local")
func _parried_event(attacker_path: NodePath) -> void:
	EventBus.player_parried.emit(get_node_or_null(attacker_path))


## Host-only debug enemy batch. Bound to the F key (see _unhandled_key_input).
## Spawns Husks in a ring near the mainland via the EnemySpawner.
func debug_spawn_enemies(count: int = 3) -> void:
	if not multiplayer.is_server() or _world_root == null:
		return
	var enemies := _world_root.get_node_or_null("Enemies")
	var mp := IslandRegistry.get_mainland_placement()
	if enemies == null or mp == null:
		return
	var base := enemies.get_child_count()
	for i in count:
		var e: Node3D = (load(HUSK_SCENE) as PackedScene).instantiate()
		e.name = "Husk_%d" % (base + i)
		var ang := TAU * float(i) / float(count)
		e.position = mp.position + Vector3(cos(ang), 20.0, sin(ang)) * 12.0
		enemies.add_child(e, true)
	print("[NetworkManager] debug-spawned %d husks" % count)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F:
		debug_spawn_enemies()


## Swaps to the World scene synchronously. change_scene_to_file() defers the
## swap to end-of-frame; for a guest joining mid-session that loses a race —
## the host's MultiplayerSpawner replication packets arrive in the same poll
## and fail to resolve paths (WorldRoot/PlayerSpawner) because the World tree
## isn't built yet, permanently poisoning that spawner's path cache. Building
## the tree inline guarantees it exists before the next packet is processed.
func _change_to_world_scene() -> void:
	var tree := get_tree()
	var world: Node = (load(WORLD_SCENE_PATH) as PackedScene).instantiate()
	var prev := tree.current_scene
	tree.root.add_child(world)
	tree.current_scene = world
	if prev != null:
		prev.queue_free()
	print("[NetworkManager] changed scene to %s" % WORLD_SCENE_PATH)


## Called by WorldRoot._ready after the world scene finishes loading on this peer.
## On the server, spawns a Player instance for the local peer plus every connected
## peer. MultiplayerSpawner replicates these to clients.
func register_world_root(wr: Node) -> void:
	_world_root = wr
	if not multiplayer.is_server():
		# Guest: tell the host our World tree is built so it spawns our player.
		# Gated on the peer connection being complete (see _notify_guest_world_ready).
		_notify_guest_world_ready()
		return
	# Brief defer so any guests still completing their scene change have their
	# MultiplayerSpawner ready to receive replicated spawns.
	await get_tree().create_timer(0.3).timeout
	if _world_root == null:
		return
	_spawn_player_for_peer(multiplayer.get_unique_id())
	# Guests are spawned via _guest_world_ready once they signal their scene is
	# ready; spawning them here would race the MultiplayerSpawner on slow clients.


func _spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _world_root == null:
		push_warning("[NetworkManager] _spawn_player_for_peer called before world ready")
		return
	var players := _world_root.get_node_or_null("Players")
	if players == null:
		push_error("[NetworkManager] /World/Players node missing")
		return
	for child in players.get_children():
		if child.get_multiplayer_authority() == peer_id:
			return  # already spawned
	var scene := load(PLAYER_SCENE_PATH) as PackedScene
	var p := scene.instantiate()
	p.name = "Player_%d" % peer_id
	p.set_multiplayer_authority(peer_id)
	# Pre-place near the mainland before add_child so the synchronizer never
	# replicates the (0,0,0) instantiation default. _on_world_loaded refines
	# this to the exact spawn anchor or the player's saved position.
	var mp := IslandRegistry.get_mainland_placement()
	if mp != null:
		p.position = mp.position + Vector3(0.0, 20.0, 0.0) + p._spawn_offset_for_peer(peer_id)
	# Set class BEFORE add_child so the MultiplayerSpawner snapshots it into the
	# spawn packet (class_id is marked spawn=true, mode Never in SRC_player).
	# This avoids an RPC-vs-spawn race; every peer receives the correct class
	# atomically with the node.
	p.class_id = _class_for_peer(peer_id)
	players.add_child(p, true)
	print("[NetworkManager] spawned Player_%d" % peer_id)
	# Restore the player's saved position from the world save, if any. Reject a
	# record near the world origin — that's a stale (0,0,0) artifact, not a real
	# saved spot; falling through lets the player spawn at the mainland anchor.
	var rec := PlayerStore.get_record(get_stable_id(peer_id))
	if not rec.is_empty() and Vector2(rec["pos"].x, rec["pos"].z).length() > 10.0:
		if peer_id == multiplayer.get_unique_id():
			p.apply_spawn_position(rec["pos"], rec["rot_y"])
		else:
			p.rpc_id(peer_id, "set_spawn_position", rec["pos"], rec["rot_y"])
	# Push authoritative time + rate to the new player so their world starts in sync.
	if peer_id != multiplayer.get_unique_id():
		TimeOfDay.rpc_id(peer_id, "sync_time", TimeOfDay.game_minutes, TimeOfDay.current_rate)
	# Reconnect any saved boat whose stable_owner_id matches this peer so it gets
	# a valid owner_peer_id for the current session.
	BoatManager.assign_owner_peer_from_stable_id(get_stable_id(peer_id), peer_id)
