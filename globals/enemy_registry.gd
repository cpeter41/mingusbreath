extends Node
# Autoload. Scans data/enemies/*.tres at boot and exposes enemy defs by id.
# Mirrors ClassRegistry — no class_name (autoloads are referenced by their
# autoload name).

const ENEMIES_DIR := "res://data/enemies/"
const DEFAULT_ENEMY_ID := &"husk"

var enemies: Dictionary = {}   # StringName -> EnemyDef


func _ready() -> void:
	_scan_enemies()


func _scan_enemies() -> void:
	var d := DirAccess.open(ENEMIES_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".tres"):
			var res := load(ENEMIES_DIR + fname)
			if res != null and "id" in res:
				enemies[StringName(res.id)] = res
		fname = d.get_next()
	d.list_dir_end()


func get_enemy_def(id: StringName) -> Resource:
	return enemies.get(id, null)


func enemy_ids() -> Array:
	var ids := enemies.keys()
	ids.sort()
	return ids


func resolve(id: StringName) -> Resource:
	var def := get_enemy_def(id)
	if def != null:
		return def
	def = get_enemy_def(DEFAULT_ENEMY_ID)
	if def != null:
		return def
	var ids := enemy_ids()
	return enemies[ids[0]] if not ids.is_empty() else null
