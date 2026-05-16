extends Node
# Saveable interface (duck-typed): save_data() -> Dictionary, load_data(d: Dictionary) -> void.
# Autoloads call SaveSystem.register(self) from _ready to participate in save/load.
#
# World saves are slot files under user://worlds/<name>.dat. The active slot is
# `current_world`, chosen in the lobby menu before a game starts.

const WORLDS_DIR := "user://worlds/"
const LEGACY_SAVE_PATH := "user://save.dat"
const SCHEMA_VERSION := 3

var current_world: String = ""

var _saveables: Array[Node] = []
var _save_disabled: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	_migrate_legacy_save()


func register(node: Node) -> void:
	if node not in _saveables:
		_saveables.append(node)


func disable_save() -> void:
	_save_disabled = true


func set_world(world_name: String) -> void:
	current_world = world_name


## Lists existing world slot names (no extension), sorted.
func list_worlds() -> PackedStringArray:
	return SlotUtil.list_slots(WORLDS_DIR)


## Creates a new (empty) world slot file and returns its final name. A 0-byte
## .dat loads cleanly via load_or_init (treated as defaults).
func create_world(base: String) -> String:
	var slot_name := SlotUtil.unique_name(WORLDS_DIR, base)
	var f := FileAccess.open(WORLDS_DIR + slot_name + ".dat", FileAccess.WRITE)
	if f != null:
		f.close()
	return slot_name


func _save_path() -> String:
	return WORLDS_DIR + current_world + ".dat"


func _temp_path() -> String:
	return WORLDS_DIR + current_world + ".tmp"


## One-time move of a legacy user://save.dat into the worlds folder.
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var target := WORLDS_DIR + "save.dat"
	if FileAccess.file_exists(target):
		return
	var d := DirAccess.open("user://")
	if d == null:
		return
	if d.copy(LEGACY_SAVE_PATH, target) == OK:
		d.remove(LEGACY_SAVE_PATH)
		print("[SaveSystem] migrated legacy save.dat -> worlds/save.dat")


func save() -> bool:
	if _save_disabled:
		return true
	# World save is host-owned. Guests skip — their per-peer state lives in
	# ProfileSave (user://characters/<name>.dat).
	if not multiplayer.is_server():
		return true
	if current_world == "":
		push_warning("SaveSystem: save() with no world selected — skipped")
		return false
	var payload := {}
	for n in _saveables:
		if n.has_method("save_data"):
			payload[n.name] = n.save_data()
	var blob := {
		"header": {"version": SCHEMA_VERSION, "seed": GameState.world_seed},
		"payload": payload,
	}
	var f := FileAccess.open(_temp_path(), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: failed to open %s for write (err=%d)" % [_temp_path(), FileAccess.get_open_error()])
		return false
	f.store_var(blob)
	f.flush()
	f.close()
	var d := DirAccess.open(WORLDS_DIR)
	if d == null:
		push_error("SaveSystem: failed to open %s for rename" % WORLDS_DIR)
		return false
	var save_file := _save_path().get_file()
	var temp_file := _temp_path().get_file()
	if d.file_exists(save_file):
		d.remove(save_file)
	var err := d.rename(temp_file, save_file)
	if err != OK:
		push_error("SaveSystem: rename failed (err=%d)" % err)
		return false
	return true


func load_or_init() -> void:
	_save_disabled = false
	# Only the host loads world state. Guests receive world state via
	# replication once spawned.
	if not multiplayer.is_server():
		return
	for i in range(_saveables.size() - 1, -1, -1):
		if not is_instance_valid(_saveables[i]):
			_saveables.remove_at(i)
	if current_world == "":
		push_warning("SaveSystem: load_or_init() with no world selected — defaults")
		for n in _saveables:
			if n.has_method("load_data"):
				n.load_data({})
		return
	if not FileAccess.file_exists(_save_path()):
		for n in _saveables:
			if n.has_method("load_data"):
				n.load_data({})
		return
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	if f == null:
		push_error("SaveSystem: failed to open %s for read (err=%d)" % [_save_path(), FileAccess.get_open_error()])
		return
	if f.get_length() == 0:
		push_warning("SaveSystem: %s is empty, starting with defaults" % _save_path())
		f.close()
		for n in _saveables:
			if n.has_method("load_data"):
				n.load_data({})
		return
	var blob = f.get_var()
	f.close()
	if typeof(blob) != TYPE_DICTIONARY or not blob.has("header") or not blob.has("payload"):
		push_warning("SaveSystem: %s malformed, starting with defaults" % _save_path())
		return
	var header: Dictionary = blob["header"]
	var version := int(header.get("version", 0))
	if version != SCHEMA_VERSION:
		push_warning("SaveSystem: save version %d != %d, wiping for cold start" % [version, SCHEMA_VERSION])
		delete_save()
		for n in _saveables:
			if n.has_method("load_data"):
				n.load_data({})
		return
	var payload: Dictionary = blob["payload"]
	payload = _migrate(payload, version)
	for n in _saveables:
		if n.has_method("load_data") and payload.has(n.name):
			n.load_data(payload[n.name])


func delete_save() -> void:
	if current_world == "":
		return
	var d := DirAccess.open(WORLDS_DIR)
	if d == null:
		return
	var save_file := _save_path().get_file()
	var temp_file := _temp_path().get_file()
	if d.file_exists(save_file):
		d.remove(save_file)
	if d.file_exists(temp_file):
		d.remove(temp_file)


func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
	if from_version > SCHEMA_VERSION:
		push_warning("SaveSystem: save is from a newer version (%d > %d); attempting to load anyway" % [from_version, SCHEMA_VERSION])
	if from_version < 2:
		if not payload.has("IslandDeltaStore"):
			payload["IslandDeltaStore"] = {}
		if not payload.has("TimeOfDay"):
			payload["TimeOfDay"] = {"game_minutes": 480.0}
		# Player key absent on v1 → load_data not called; fresh-spawn path takes over.
	# v2→v3: boat velocity fields added to BoatManager save; BoatManager.load_data
	# handles missing keys via bd.has(), so no payload rewrite is needed here.
	return payload
