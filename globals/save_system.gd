extends Node
# Saveable interface (duck-typed): save_data() -> Dictionary, load_data(d: Dictionary) -> void.
# Autoloads call SaveSystem.register(self) from _ready to participate in save/load.

const SAVE_PATH := "user://save.dat"
const TEMP_PATH := "user://save.tmp"
const SCHEMA_VERSION := 3

var _saveables: Array[Node] = []
var _save_disabled: bool = false

func register(node: Node) -> void:
	if node not in _saveables:
		_saveables.append(node)

func disable_save() -> void:
	_save_disabled = true

func save() -> bool:
	if _save_disabled:
		return true
	var payload := {}
	for n in _saveables:
		if n.has_method("save_data"):
			payload[n.name] = n.save_data()
	var blob := {
		"header": {"version": SCHEMA_VERSION, "seed": GameState.world_seed},
		"payload": payload,
	}
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: failed to open %s for write (err=%d)" % [TEMP_PATH, FileAccess.get_open_error()])
		return false
	f.store_var(blob)
	f.flush()
	f.close()
	var d := DirAccess.open("user://")
	if d == null:
		push_error("SaveSystem: failed to open user:// for rename")
		return false
	if d.file_exists(SAVE_PATH.get_file()):
		d.remove(SAVE_PATH.get_file())
	var err := d.rename(TEMP_PATH.get_file(), SAVE_PATH.get_file())
	if err != OK:
		push_error("SaveSystem: rename failed (err=%d)" % err)
		return false
	return true

func load_or_init() -> void:
	_save_disabled = false
	for i in range(_saveables.size() - 1, -1, -1):
		if not is_instance_valid(_saveables[i]):
			_saveables.remove_at(i)
	if not FileAccess.file_exists(SAVE_PATH):
		for n in _saveables:
			if n.has_method("load_data"):
				n.load_data({})
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("SaveSystem: failed to open %s for read (err=%d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	if f.get_length() == 0:
		push_warning("SaveSystem: %s is empty, starting with defaults" % SAVE_PATH)
		f.close()
		return
	var blob = f.get_var()
	f.close()
	if typeof(blob) != TYPE_DICTIONARY or not blob.has("header") or not blob.has("payload"):
		push_warning("SaveSystem: %s malformed, starting with defaults" % SAVE_PATH)
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
	var d := DirAccess.open("user://")
	if d == null:
		return
	if d.file_exists(SAVE_PATH.get_file()):
		d.remove(SAVE_PATH.get_file())
	if d.file_exists(TEMP_PATH.get_file()):
		d.remove(TEMP_PATH.get_file())

func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
	if from_version > SCHEMA_VERSION:
		push_warning("SaveSystem: save is from a newer version (%d > %d); attempting to load anyway" % [from_version, SCHEMA_VERSION])
	if from_version < 2:
		if not payload.has("IslandDeltaStore"):
			payload["IslandDeltaStore"] = {}
		if not payload.has("TimeOfDay"):
			payload["TimeOfDay"] = {"game_minutes": 480.0}
		# Player key absent on v1 → load_data not called; fresh-spawn path takes over.
	return payload
