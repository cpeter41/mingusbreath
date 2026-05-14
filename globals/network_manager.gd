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

var mode: int = Mode.OFFLINE
var local_peer_id: int = 1
var peers: Dictionary = {}  # peer_id -> {steam_id, display_name}

var _use_enet_fallback: bool = false
var _enet_host_ip: String = "127.0.0.1"
var _world_loaded: bool = false
var _world_root: Node = null  # set by WorldRoot._ready after scene swap


func _ready() -> void:
	print("[NetworkManager] ready (mode=OFFLINE)")
	_parse_cmdline()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# Auto-start based on cmdline so two Godot instances can be wired up via run args.
	if _use_enet_fallback:
		var args := OS.get_cmdline_args()
		if "--host" in args:
			# Defer so autoloads finish ready before scene change.
			call_deferred("_cmdline_autostart_host")
		elif "--join" in args:
			call_deferred("_cmdline_autostart_client")


func _cmdline_autostart_host() -> void:
	start_host()
	# Give a moment for any --join client on the same machine to connect, then load world.
	await get_tree().create_timer(2.0).timeout
	load_world()


func _cmdline_autostart_client() -> void:
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
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	peers.clear()
	print("[NetworkManager] disconnected, back to OFFLINE")


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
		# If we've already entered the world, push the new guest into it too,
		# then spawn their Player after they finish the scene change.
		if _world_loaded:
			rpc_id(peer_id, "_remote_load_world")
			# Defer a bit so the guest's scene swap completes before spawn replicates.
			await get_tree().create_timer(1.0).timeout
			_spawn_player_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] peer_disconnected: %d" % peer_id)
	peers.erase(peer_id)
	peer_player_left.emit(peer_id)
	roster_changed.emit()
	if multiplayer.is_server():
		rpc("_sync_roster", peers)


func _on_server_disconnected() -> void:
	push_warning("[NetworkManager] server disconnected")
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
	_world_loaded = true
	world_loaded.emit()
	_change_to_world_scene()


@rpc("authority", "reliable", "call_remote")
func _sync_roster(new_roster: Dictionary) -> void:
	peers = new_roster
	roster_changed.emit()


func _change_to_world_scene() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)
	print("[NetworkManager] changed scene to %s" % WORLD_SCENE_PATH)


## Called by WorldRoot._ready after the world scene finishes loading on this peer.
## On the server, spawns a Player instance for the local peer plus every connected
## peer. MultiplayerSpawner replicates these to clients.
func register_world_root(wr: Node) -> void:
	_world_root = wr
	if not multiplayer.is_server():
		return
	# Brief defer so any guests still completing their scene change have their
	# MultiplayerSpawner ready to receive replicated spawns.
	await get_tree().create_timer(0.3).timeout
	if _world_root == null:
		return
	_spawn_player_for_peer(multiplayer.get_unique_id())
	for peer_id in peers.keys():
		_spawn_player_for_peer(peer_id)


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
	players.add_child(p, true)
	print("[NetworkManager] spawned Player_%d" % peer_id)
	# Push authoritative time + rate to the new player so their world starts in sync.
	if peer_id != multiplayer.get_unique_id():
		TimeOfDay.rpc_id(peer_id, "sync_time", TimeOfDay.game_minutes, TimeOfDay.current_rate)
