extends Node

const ITEMS_DIR := "res://data/items/"

var items: Dictionary = {}

func _ready() -> void:
	_scan_items()

func _scan_items() -> void:
	var d := DirAccess.open(ITEMS_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".tres"):
			var res := load(ITEMS_DIR + fname)
			if res != null and "id" in res:
				items[StringName(res.id)] = res
		fname = d.get_next()
	d.list_dir_end()

func get_item(id: StringName) -> Resource:
	return items.get(id, null)
