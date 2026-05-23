extends Control
# Pre-game lobby. Pick a save slot (World + Character), then host / join / solo.
#
# Works in two transports:
# - Steam: uses SteamLobby to create/join Steam lobbies (friends-only).
# - Local: ENet on 127.0.0.1:ENET_PORT for two-instance dev testing.
#
# Cmdline `--offline --host` / `--offline --join <ip>` skips this scene entirely
# (NetworkManager auto-starts in _ready and uses a "default" slot).
#
# Slot rules:
# - Host / Solo require both a World and a Character selected.
# - Join requires only a Character (the guest joins the host's world).

@onready var _title: Label = $Columns/VBox/Title
@onready var _status: Label = $Columns/VBox/Status
@onready var _roster: Label = $Columns/VBox/Roster
@onready var _btn_host_steam: Button = $Columns/VBox/HostSteam
@onready var _btn_host_local: Button = $Columns/VBox/HostLocal
@onready var _btn_join_local: Button = $Columns/VBox/JoinLocal
@onready var _btn_solo: Button = $Columns/VBox/Solo
@onready var _btn_start: Button = $Columns/VBox/StartGame
@onready var _btn_leave: Button = $Columns/VBox/Leave
@onready var _join_ip_edit: LineEdit = $Columns/VBox/JoinIP

@onready var _world_dropdown: OptionButton = $Columns/SlotsColumn/WorldDropdown
@onready var _world_name_edit: LineEdit = $Columns/SlotsColumn/WorldCreate/WorldNameEdit
@onready var _world_add_btn: Button = $Columns/SlotsColumn/WorldCreate/WorldAddBtn
@onready var _char_dropdown: OptionButton = $Columns/SlotsColumn/CharDropdown
@onready var _char_name_edit: LineEdit = $Columns/SlotsColumn/CharCreate/CharNameEdit
@onready var _char_add_btn: Button = $Columns/SlotsColumn/CharCreate/CharAddBtn
@onready var _class_dropdown: OptionButton = $Columns/SlotsColumn/ClassDropdown


func _ready() -> void:
	_btn_host_steam.pressed.connect(_on_host_steam)
	_btn_host_local.pressed.connect(_on_host_local)
	_btn_join_local.pressed.connect(_on_join_local)
	_btn_solo.pressed.connect(_on_solo)
	_btn_start.pressed.connect(_on_start)
	_btn_leave.pressed.connect(_on_leave)

	_world_dropdown.item_selected.connect(_on_world_selected)
	_char_dropdown.item_selected.connect(_on_char_selected)
	_world_add_btn.pressed.connect(_on_world_add)
	_char_add_btn.pressed.connect(_on_char_add)
	# Class dropdown is interactive only while the user is typing a new
	# character name; otherwise it read-only-displays the selected character's
	# locked class (class is fixed at character creation).
	_char_name_edit.text_changed.connect(_on_char_name_edit_text_changed)

	NetworkManager.mode_changed.connect(_on_mode_changed)
	NetworkManager.peer_player_joined.connect(_on_peer_joined)
	NetworkManager.peer_player_left.connect(_on_peer_left)
	NetworkManager.roster_changed.connect(_refresh_roster)
	NetworkManager.world_loaded.connect(_on_world_loaded)

	_btn_host_steam.disabled = not SteamLobby.available
	if not SteamLobby.available:
		_btn_host_steam.text = "Host (Steam unavailable)"

	_refresh_world_dropdown()
	_refresh_char_dropdown()
	_refresh_class_dropdown()
	_set_status("Idle")
	_refresh_buttons()
	_refresh_roster()


# ── Save slots ───────────────────────────────────────────────────

func _refresh_world_dropdown() -> void:
	_world_dropdown.clear()
	for w in SaveSystem.list_worlds():
		_world_dropdown.add_item(w)
	# Sync the active selection back to SaveSystem (or clear it).
	if _world_dropdown.item_count > 0:
		if SaveSystem.current_world == "":
			_world_dropdown.select(0)
			SaveSystem.set_world(_world_dropdown.get_item_text(0))
		else:
			_select_dropdown_text(_world_dropdown, SaveSystem.current_world)
	else:
		SaveSystem.set_world("")


func _refresh_char_dropdown() -> void:
	_char_dropdown.clear()
	for c in ProfileSave.list_characters():
		var idx := _char_dropdown.item_count
		_char_dropdown.add_item(_char_label(c))
		# Slot name in metadata — the displayed text now includes the class
		# in parens and is not the slot identifier on disk.
		_char_dropdown.set_item_metadata(idx, c)
	if _char_dropdown.item_count > 0:
		if ProfileSave.current_character == "":
			_char_dropdown.select(0)
			ProfileSave.set_character(_char_dropdown.get_item_metadata(0))
		else:
			_select_char_dropdown_slot(ProfileSave.current_character)
	else:
		ProfileSave.set_character("")


# "Hero1 (Bulwark)" — class display name resolved from ClassRegistry, falls
# back to the raw class id, then to bare slot name if even that's missing.
func _char_label(slot_name: String) -> String:
	var cid := ProfileSave.get_character_class(slot_name)
	var def := ClassRegistry.get_class_def(cid)
	var class_label: String = ""
	if def != null and def.display_name != "":
		class_label = def.display_name
	elif cid != &"":
		class_label = String(cid)
	if class_label == "":
		return slot_name
	return "%s (%s)" % [slot_name, class_label]


func _select_char_dropdown_slot(slot_name: String) -> void:
	for i in _char_dropdown.item_count:
		if _char_dropdown.get_item_metadata(i) == slot_name:
			_char_dropdown.select(i)
			return
	if _char_dropdown.item_count > 0:
		_char_dropdown.select(0)


func _select_dropdown_text(dd: OptionButton, text: String) -> void:
	for i in dd.item_count:
		if dd.get_item_text(i) == text:
			dd.select(i)
			return
	# Selection no longer exists — fall back to first item.
	if dd.item_count > 0:
		dd.select(0)


func _on_world_selected(idx: int) -> void:
	SaveSystem.set_world(_world_dropdown.get_item_text(idx))
	_refresh_buttons()
	_refresh_roster()


func _on_char_selected(idx: int) -> void:
	# Read the slot name from metadata — the displayed text is decorated.
	ProfileSave.set_character(_char_dropdown.get_item_metadata(idx))
	_sync_class_dropdown_state()   # reflect the new character's locked class
	_refresh_buttons()
	_refresh_roster()


func _on_char_name_edit_text_changed(_text: String) -> void:
	_sync_class_dropdown_state()


# ── Class dropdown ───────────────────────────────────────────────
# Class is fixed at character creation. The dropdown serves the *next-created*
# character (only used by _on_char_add); for an existing selected character it
# shows that character's locked class read-only.

func _refresh_class_dropdown() -> void:
	_class_dropdown.clear()
	for cid in ClassRegistry.class_ids():
		var def := ClassRegistry.get_class_def(cid)
		var label: String = def.display_name if def != null and def.display_name != "" else String(cid)
		var idx := _class_dropdown.item_count
		_class_dropdown.add_item(label)
		_class_dropdown.set_item_metadata(idx, cid)
	_sync_class_dropdown_state()


# Enabled while typing a new character name; otherwise shows the selected
# character's locked class, read-only. Also locks once a session starts.
func _sync_class_dropdown_state() -> void:
	var creating := _char_name_edit.text.strip_edges() != ""
	if not creating and ProfileSave.current_character != "":
		var cur := ProfileSave.current_class()
		for i in _class_dropdown.item_count:
			if _class_dropdown.get_item_metadata(i) == cur:
				_class_dropdown.select(i)
				break
	_class_dropdown.disabled = (not creating) or (not NetworkManager.is_offline())


func _on_world_add() -> void:
	var base := _world_name_edit.text.strip_edges()
	if base == "":
		return
	var created := SaveSystem.create_world(base)
	_world_name_edit.text = ""
	_refresh_world_dropdown()
	_select_dropdown_text(_world_dropdown, created)
	SaveSystem.set_world(created)
	_set_status("Created world '%s'" % created)
	_refresh_buttons()
	_refresh_roster()


func _on_char_add() -> void:
	var base := _char_name_edit.text.strip_edges()
	if base == "":
		return
	# Read the chosen class BEFORE clearing the field — the dropdown will snap
	# back to the new character's locked class on _sync_class_dropdown_state.
	var chosen_class: StringName = &""
	if _class_dropdown.selected >= 0:
		chosen_class = _class_dropdown.get_item_metadata(_class_dropdown.selected)
	var created := ProfileSave.create_character(base)
	if chosen_class != &"":
		ProfileSave.set_character_class(created, chosen_class)
	_char_name_edit.text = ""
	_refresh_char_dropdown()
	_select_char_dropdown_slot(created)
	ProfileSave.set_character(created)
	_sync_class_dropdown_state()
	_set_status("Created character '%s'" % created)
	_refresh_buttons()
	_refresh_roster()


# ── Host / join / solo ───────────────────────────────────────────

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
	var has_world := SaveSystem.current_world != ""
	var has_char := ProfileSave.current_character != ""
	# Host / Solo need both slots; Join needs only a character.
	_btn_host_steam.disabled = connected or not SteamLobby.available or not has_world or not has_char
	_btn_host_local.disabled = connected or not has_world or not has_char
	_btn_solo.disabled = connected or not has_world or not has_char
	_btn_join_local.disabled = connected or not has_char
	_btn_start.disabled = not NetworkManager.is_host()
	_btn_leave.disabled = not connected
	# Slot pickers lock once a session is underway.
	_world_dropdown.disabled = connected
	_char_dropdown.disabled = connected
	_world_add_btn.disabled = connected
	_char_add_btn.disabled = connected
	_sync_class_dropdown_state()   # also session-locks the class dropdown


func _refresh_roster() -> void:
	var lines: PackedStringArray = []
	lines.append("Mode: %s" % NetworkManager.Mode.keys()[NetworkManager.mode])
	lines.append("World: %s" % (SaveSystem.current_world if SaveSystem.current_world != "" else "<none>"))
	lines.append("Character: %s" % (ProfileSave.current_character if ProfileSave.current_character != "" else "<none>"))
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
