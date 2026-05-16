extends Node
# Per-peer local profile — skills, inventory.
#
# Distinct from SaveSystem (which holds host-owned WORLD state). Every peer,
# host or guest, owns its own character profile. Because the game is
# owner-authoritative, each peer's SkillManager / Inventory run locally — there
# is no server round-trip; a peer simply saves and loads its own file.
#
# Profiles are slot files under user://characters/<name>.dat. The active slot is
# `current_character`, chosen in the lobby menu before a game starts.
#
# Saveable interface (duck-typed): save_data() -> Dictionary,
# load_data(d: Dictionary) -> void. Register with an explicit stable key so
# entries survive peer-id changes between sessions.

const CHARACTERS_DIR := "user://characters/"
const LEGACY_PROFILE_PATH := "user://profile.dat"
const SCHEMA_VERSION := 1

var current_character: String = ""

var _entries: Array = []  # Array of { "node": Node, "key": String }
var _disabled: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CHARACTERS_DIR)
	_migrate_legacy_profile()


## key defaults to node.name. Pass an explicit key for nodes whose name varies
## between runs (e.g. Player_<peer_id> — register it as "Player").
func register(node: Node, key: String = "") -> void:
	var k: String = key if key != "" else String(node.name)
	for e in _entries:
		if e["node"] == node:
			return
	_entries.append({"node": node, "key": k})


func disable_save() -> void:
	_disabled = true


func set_character(char_name: String) -> void:
	current_character = char_name


## Lists existing character slot names (no extension), sorted.
func list_characters() -> PackedStringArray:
	return SlotUtil.list_slots(CHARACTERS_DIR)


## Creates a new (empty) character slot file and returns its final name.
func create_character(base: String) -> String:
	var slot_name := SlotUtil.unique_name(CHARACTERS_DIR, base)
	var f := FileAccess.open(CHARACTERS_DIR + slot_name + ".dat", FileAccess.WRITE)
	if f != null:
		f.close()
	return slot_name


func _profile_path() -> String:
	return CHARACTERS_DIR + current_character + ".dat"


func _temp_path() -> String:
	return CHARACTERS_DIR + current_character + ".tmp"


## One-time move of a legacy user://profile.dat into the characters folder.
func _migrate_legacy_profile() -> void:
	if not FileAccess.file_exists(LEGACY_PROFILE_PATH):
		return
	var target := CHARACTERS_DIR + "profile.dat"
	if FileAccess.file_exists(target):
		return
	var d := DirAccess.open("user://")
	if d == null:
		return
	if d.copy(LEGACY_PROFILE_PATH, target) == OK:
		d.remove(LEGACY_PROFILE_PATH)
		print("[ProfileSave] migrated legacy profile.dat -> characters/profile.dat")


func save() -> bool:
	if _disabled:
		return true
	if current_character == "":
		push_warning("ProfileSave: save() with no character selected — skipped")
		return false
	var payload := {}
	for e in _entries:
		var n: Node = e["node"]
		if is_instance_valid(n) and n.has_method("save_data"):
			payload[e["key"]] = n.save_data()
	var blob := {"header": {"version": SCHEMA_VERSION}, "payload": payload}
	var f := FileAccess.open(_temp_path(), FileAccess.WRITE)
	if f == null:
		push_error("ProfileSave: failed to open %s for write (err=%d)" % [_temp_path(), FileAccess.get_open_error()])
		return false
	f.store_var(blob)
	f.flush()
	f.close()
	var d := DirAccess.open(CHARACTERS_DIR)
	if d == null:
		push_error("ProfileSave: failed to open %s for rename" % CHARACTERS_DIR)
		return false
	var profile_file := _profile_path().get_file()
	var temp_file := _temp_path().get_file()
	if d.file_exists(profile_file):
		d.remove(profile_file)
	var err := d.rename(temp_file, profile_file)
	if err != OK:
		push_error("ProfileSave: rename failed (err=%d)" % err)
		return false
	return true


func load_or_init() -> void:
	_disabled = false
	for i in range(_entries.size() - 1, -1, -1):
		if not is_instance_valid(_entries[i]["node"]):
			_entries.remove_at(i)
	if current_character == "":
		push_warning("ProfileSave: load_or_init() with no character selected — defaults")
		_apply_defaults()
		return
	if not FileAccess.file_exists(_profile_path()):
		_apply_defaults()
		return
	var f := FileAccess.open(_profile_path(), FileAccess.READ)
	if f == null:
		push_error("ProfileSave: failed to open %s for read (err=%d)" % [_profile_path(), FileAccess.get_open_error()])
		return
	if f.get_length() == 0:
		f.close()
		_apply_defaults()
		return
	var blob = f.get_var()
	f.close()
	if typeof(blob) != TYPE_DICTIONARY or not blob.has("header") or not blob.has("payload"):
		push_warning("ProfileSave: %s malformed, starting fresh" % _profile_path())
		_apply_defaults()
		return
	var version := int((blob["header"] as Dictionary).get("version", 0))
	if version != SCHEMA_VERSION:
		push_warning("ProfileSave: profile version %d != %d, wiping" % [version, SCHEMA_VERSION])
		delete_profile()
		_apply_defaults()
		return
	var payload: Dictionary = blob["payload"]
	for e in _entries:
		var n: Node = e["node"]
		if is_instance_valid(n) and n.has_method("load_data") and payload.has(e["key"]):
			n.load_data(payload[e["key"]])


func delete_profile() -> void:
	if current_character == "":
		return
	var d := DirAccess.open(CHARACTERS_DIR)
	if d == null:
		return
	var profile_file := _profile_path().get_file()
	var temp_file := _temp_path().get_file()
	if d.file_exists(profile_file):
		d.remove(profile_file)
	if d.file_exists(temp_file):
		d.remove(temp_file)


func _apply_defaults() -> void:
	for e in _entries:
		var n: Node = e["node"]
		if is_instance_valid(n) and n.has_method("load_data"):
			n.load_data({})
