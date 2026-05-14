## ZoneMap autoload.
## Holds generated difficulty zones. Call compute() after world_seed is loaded
## and BEFORE IslandPlacer.place() so placement can query classify().
extends Node

signal debug_toggled(visible: bool)

var zones: Array = []  # Array[ZoneInstance]
var debug_visible: bool = false


func set_debug_visible(v: bool) -> void:
	if debug_visible == v:
		return
	debug_visible = v
	debug_toggled.emit(v)


func compute(world_seed: int, world_size_m: float) -> void:
	zones = ZoneGenerator.generate(world_seed, world_size_m)


func get_zone(p: Vector3) -> ZoneInstance:
	var best: ZoneInstance = null
	var best_f := -INF
	for z in zones:
		var f := (z as ZoneInstance).field_at(p)
		if f > best_f:
			best_f = f
			best = z
	return best


func classify(p: Vector3) -> int:
	var z := get_zone(p)
	if z == null:
		return Difficulty.EASY
	return z.def.difficulty
