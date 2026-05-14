extends Node
# Steam lobby wrapper around GodotSteam GDExtension.
# If Steam class is unavailable (extension missing) or Steam client is not running,
# `available` stays false and NetworkManager falls back to ENet transport.

signal lobby_ready(lobby_id: int)
signal lobby_joined(host_steam_id: int)
signal lobby_left
signal lobby_chat_update(lobby_id: int, change_id: int, making_change_id: int, chat_state: int)

const APP_ID_SPACEWAR := 480

var lobby_id: int = 0
var available: bool = false
var steam_id: int = 0
var steam_name: String = ""


func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		print("[SteamLobby] Steam singleton missing — GodotSteam not loaded. ENet fallback only.")
		return

	# Steam class lives at global scope when extension is registered.
	var init_result: Dictionary = Steam.steamInitEx(APP_ID_SPACEWAR, true)
	# steamInitEx returns {status: int, verbal: String}
	# status: 0 = ok, 1 = failed generic, 2 = no connection, 3 = version mismatch
	if init_result.get("status", -1) != 0:
		print("[SteamLobby] Steam init failed: %s. ENet fallback only." % init_result)
		return

	available = true
	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()
	print("[SteamLobby] Steam OK — id=%d name=%s" % [steam_id, steam_name])

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	# Fires when user clicks "Join Game" on a Steam friend in the Steam UI/overlay,
	# or accepts a lobby invite. Auto-join.
	Steam.join_requested.connect(_on_lobby_join_requested)
	# Steam callbacks must be pumped each frame:
	set_process(true)


func _process(_dt: float) -> void:
	if available:
		Steam.run_callbacks()


func host_lobby(max_players: int = 4) -> void:
	if not available:
		push_warning("[SteamLobby] host_lobby called but Steam unavailable")
		return
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_players)


func join_lobby(target_lobby_id: int) -> void:
	if not available:
		push_warning("[SteamLobby] join_lobby called but Steam unavailable")
		return
	Steam.joinLobby(target_lobby_id)


func leave_lobby() -> void:
	if not available or lobby_id == 0:
		return
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	lobby_left.emit()


func _on_lobby_created(connect_result: int, new_lobby_id: int) -> void:
	if connect_result != 1:
		push_error("[SteamLobby] lobby create failed: %d" % connect_result)
		return
	lobby_id = new_lobby_id
	Steam.setLobbyData(lobby_id, "game", "mingusbreath")
	print("[SteamLobby] lobby created: %d" % lobby_id)
	lobby_ready.emit(lobby_id)
	# Host now needs to start the transport peer so guests can connect.
	NetworkManager.start_host()


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("[SteamLobby] join failed: response=%d" % response)
		return
	lobby_id = joined_lobby_id
	var owner_id: int = Steam.getLobbyOwner(joined_lobby_id)
	print("[SteamLobby] joined lobby %d (owner=%d)" % [joined_lobby_id, owner_id])
	lobby_joined.emit(owner_id)
	NetworkManager.start_client(owner_id)


func _on_lobby_chat_update(this_lobby_id: int, change_id: int, making_change_id: int, chat_state: int) -> void:
	lobby_chat_update.emit(this_lobby_id, change_id, making_change_id, chat_state)


func _on_lobby_join_requested(target_lobby_id: int, _friend_steam_id: int) -> void:
	print("[SteamLobby] join requested for lobby %d (from Steam overlay/invite)" % target_lobby_id)
	join_lobby(target_lobby_id)
