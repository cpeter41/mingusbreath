## IslandRegistry autoload.
## Adding islands may shuffle non-starter placements when world_seed is reused.
extends Node

const ISLANDS_DIR := "res://data/islands/"
const WORLD_SIZE_M := 8192.0
const ISLAND_COUNT := 8

var _defs: Array = []  # Array[IslandDef]
var placements: Array = []  # Array[IslandPlacement] — empty until compute_placements()


func _ready() -> void:
	_load_defs()


func _load_defs() -> void:
	var d := DirAccess.open(ISLANDS_DIR)
	if d == null:
		push_error("IslandRegistry: cannot open %s" % ISLANDS_DIR)
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".tres"):
			var res := load(ISLANDS_DIR + fname)
			if res != null and res is IslandDef:
				_defs.append(res)
		fname = d.get_next()
	d.list_dir_end()


## Call after SaveSystem.load_or_init() so world_seed is correct.
## Idempotent — safe to call again after seed change.
func compute_placements() -> void:
	placements = IslandPlacer.place(_defs, GameState.world_seed, WORLD_SIZE_M, ISLAND_COUNT)


func get_mainland_placement() -> IslandPlacement:
	for p in placements:
		if p.def.id == IslandPlacer.MAINLAND_DEF_ID:
			return p
	return null


func get_placement_by_runtime_id(runtime_id: StringName) -> IslandPlacement:
	for p in placements:
		if p.runtime_id == runtime_id:
			return p
	return null
