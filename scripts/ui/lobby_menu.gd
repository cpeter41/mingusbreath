extends Control
# Pre-game lobby. Host or join, see roster, click Start to load the world.
#
# Works in two transports:
# - Steam: uses SteamLobby to create/join Steam lobbies (friends-only).
# - Local: ENet on 127.0.0.1:ENET_PORT for two-instance dev testing.
#
# Cmdline `--offline --host` / `--offline --join <ip>` skips this scene entirely
# (NetworkManager auto-starts in _ready and loads World after 2s).

@onready var _title: Label = $VBox/Title
@onready var _status: Label = $VBox/Status
@onready var _roster: Label = $VBox/Roster
@onready var _btn_host_steam: Button = $VBox/HostSteam
@onready var _btn_host_local: Button = $VBox/HostLocal
@onready var _btn_join_local: Button = $VBox/JoinLocal
@onready var _btn_solo: Button = $VBox/Solo
@onready var _btn_start: Button = $VBox/StartGame
@onready var _btn_leave: Button = $VBox/Leave
@onready var _join_ip_edit: LineEdit = $VBox/JoinIP


func _ready() -> void:
	_btn_host_steam.pressed.connect(_on_host_steam)
	_btn_host_local.pressed.connect(_on_host_local)
	_btn_join_local.pressed.connect(_on_join_local)
	_btn_solo.pressed.connect(_on_solo)
	_btn_start.pressed.connect(_on_start)
	_btn_leave.pressed.connect(_on_leave)

	NetworkManager.mode_changed.connect(_on_mode_changed)
	NetworkManager.peer_player_joined.connect(_on_peer_joined)
	NetworkManager.peer_player_left.connect(_on_peer_left)
	NetworkManager.roster_changed.connect(_refresh_roster)
	NetworkManager.world_loaded.connect(_on_world_loaded)

	_btn_host_steam.disabled = not SteamLobby.available
	if not SteamLobby.available:
		_btn_host_steam.text = "Host (Steam unavailable)"

	_set_status("Idle")
	_refresh_buttons()
	_refresh_roster()


func _on_host_steam() -> void:
	_set_status("Creating Steam lobby...")
	SteamLobby.host_lobby(4)


func _on_host_local() -> void:
	_set_status("Hosting on 127.0.0.1:%d" % NetworkManager.ENET_PORT)
	# Force ENet path regardless of Steam availability for local dev tests.
	NetworkManager._use_enet_fallback = true
	NetworkManager.start_host()


func _on_join_local() -> void:
	var ip := _join_ip_edit.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	_set_status("Joining %s:%d ..." % [ip, NetworkManager.ENET_PORT])
	NetworkManager._use_enet_fallback = true
	NetworkManager.start_client(ip)


func _on_solo() -> void:
	NetworkManager.load_world()


func _on_start() -> void:
	if NetworkManager.is_host() or NetworkManager.is_offline():
		NetworkManager.load_world()


func _on_leave() -> void:
	NetworkManager.disconnect_all()
	if SteamLobby.available and SteamLobby.lobby_id != 0:
		SteamLobby.leave_lobby()
	_set_status("Disconnected")
	_refresh_buttons()
	_refresh_roster()


func _on_mode_changed(_is_host: bool) -> void:
	_refresh_buttons()
	_refresh_roster()


func _on_peer_joined(peer_id: int, _steam_id: int) -> void:
	_set_status("Peer %d joined" % peer_id)
	_refresh_roster()


func _on_peer_left(peer_id: int) -> void:
	_set_status("Peer %d left" % peer_id)
	_refresh_roster()


func _on_world_loaded() -> void:
	_set_status("Loading world...")


func _refresh_buttons() -> void:
	var connected := not NetworkManager.is_offline()
	_btn_host_steam.disabled = connected or not SteamLobby.available
	_btn_host_local.disabled = connected
	_btn_join_local.disabled = connected
	_btn_solo.disabled = connected
	_btn_start.disabled = not NetworkManager.is_host()
	_btn_leave.disabled = not connected


func _refresh_roster() -> void:
	var lines: PackedStringArray = []
	lines.append("Mode: %s" % NetworkManager.Mode.keys()[NetworkManager.mode])
	if SteamLobby.available and SteamLobby.lobby_id != 0:
		lines.append("Steam lobby: %d" % SteamLobby.lobby_id)
	lines.append("Peers (%d):" % NetworkManager.peers.size())
	for pid in NetworkManager.peers.keys():
		var rec: Dictionary = NetworkManager.peers[pid]
		lines.append("  - %d (%s)" % [pid, rec.get("display_name", "?")])
	_roster.text = "\n".join(lines)


func _set_status(s: String) -> void:
	_status.text = s
	print("[LobbyMenu] %s" % s)
