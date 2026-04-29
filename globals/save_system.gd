extends Node
# Saveable interface (duck-typed): save_data() -> Dictionary, load_data(d: Dictionary) -> void.
# Autoloads call SaveSystem.register(self) from _ready to participate in save/load.

const SAVE_PATH := "user://save.dat"
const TEMP_PATH := "user://save.tmp"
const SCHEMA_VERSION := 1

var _saveables: Array[Node] = []

func register(node: Node) -> void:
	if node not in _saveables:
		_saveables.append(node)

func save() -> bool:
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
	if not FileAccess.file_exists(SAVE_PATH):
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
	var payload: Dictionary = blob["payload"]
	payload = _migrate(payload, version)
	for n in _saveables:
		if n.has_method("load_data") and payload.has(n.name):
			n.load_data(payload[n.name])

func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
	# v1 is current. Future migrations chain here, e.g.
	# if from_version < 2: payload = _v1_to_v2(payload)
	if from_version > SCHEMA_VERSION:
		push_warning("SaveSystem: save is from a newer version (%d > %d); attempting to load anyway" % [from_version, SCHEMA_VERSION])
	return payload
