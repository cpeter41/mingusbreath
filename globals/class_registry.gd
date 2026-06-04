extends Node
# Autoload. Scans data/classes/*.tres at boot and exposes class defs by id.
# Mirrors InventoryRegistry / SkillManager — no class_name (autoloads are
# referenced by their autoload name; a class_name would clash).

const CLASSES_DIR := "res://data/classes/"
const DEFAULT_CLASS_ID := &"bulwark"   # fallback; must name a shipped class

var classes: Dictionary = {}   # StringName -> ClassDef


func _ready() -> void:
	_scan_classes()


func _scan_classes() -> void:
	var d := DirAccess.open(CLASSES_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".tres"):
			var res := load(CLASSES_DIR + fname)
			if res != null and "id" in res:
				classes[StringName(res.id)] = res
		fname = d.get_next()
	d.list_dir_end()


## Typed as Resource (not ClassDef) to match InventoryRegistry.get_item style and
## to avoid depending on the class_name global cache at autoload-parse time.
func get_class_def(id: StringName) -> Resource:
	return classes.get(id, null)


## Stable sorted list of ids — used by the lobby class dropdown.
func class_ids() -> Array:
	var ids := classes.keys()
	ids.sort()
	return ids


## Returns the requested ClassDef, or DEFAULT_CLASS_ID, or any class found.
## Returns null only if data/classes/ is empty.
func resolve(id: StringName) -> Resource:
	var def := get_class_def(id)
	if def != null:
		return def
	def = get_class_def(DEFAULT_CLASS_ID)
	if def != null:
		return def
	var ids := class_ids()
	return classes[ids[0]] if not ids.is_empty() else null
