## Autoload name kept for back-compat. Internals are island-streaming, not chunk-grid streaming. See Phase 5 plan.
extends Node

const LOAD_BUFFER_M   := 200.0
const UNLOAD_BUFFER_M := 400.0
const OCEAN_BIOME_PATH := "res://data/biomes/ocean.tres"

var active_islands: Dictionary = {}  # StringName (runtime_id) -> Node3D

var _player: Node3D = null
var _container: Node3D = null
var _delta_store: IslandDeltaStore = null
var _first_batch_done: bool = false
var _last_active_biome: BiomeDef = null
var _ocean_biome: BiomeDef = null


func _ready() -> void:
	var s := IslandDeltaStore.new()
	s.name = "IslandDeltaStore"
	add_child(s)
	_delta_store = s


func set_player(p: Node3D) -> void:
	_player = p
	_try_first_batch()


func set_container(c: Node3D) -> void:
	# Reset stale autoload state from any previous scene load.
	_player = null
	_first_batch_done = false
	_last_active_biome = null
	active_islands.clear()
	_container = c
	_try_first_batch()


func _try_first_batch() -> void:
	if _player == null or _container == null or _first_batch_done:
		return
	for p in IslandRegistry.placements:
		var placement := p as IslandPlacement
		var dist: float = _player.global_position.distance_to(placement.position)
		if dist <= placement.def.footprint_radius + LOAD_BUFFER_M:
			_load_island(placement)
	_first_batch_done = true
	EventBus.world_loaded.emit()


func _process(_dt: float) -> void:
	if _player != null and (not is_instance_valid(_player) or not _player.is_inside_tree()):
		_player = null
	if _player == null or _container == null or not _first_batch_done:
		return

	for p in IslandRegistry.placements:
		var placement := p as IslandPlacement
		var dist: float = _player.global_position.distance_to(placement.position)
		var load_t: float = placement.def.footprint_radius + LOAD_BUFFER_M
		var unload_t: float = placement.def.footprint_radius + UNLOAD_BUFFER_M

		if dist <= load_t and not active_islands.has(placement.runtime_id):
			_load_island(placement)
		elif dist > unload_t and active_islands.has(placement.runtime_id):
			_unload_island(placement.runtime_id)

	_update_biome()


func _load_island(placement: IslandPlacement) -> void:
	var instance: Node3D = placement.def.scene.instantiate()
	instance.position = placement.position
	instance.rotation.y = placement.rotation_y
	_container.add_child(instance)
	_apply_deltas_to_instance(instance, placement, _delta_store.get_deltas_for(placement.runtime_id))
	active_islands[placement.runtime_id] = instance
	EventBus.island_loaded.emit(placement, instance)
	print("[WorldStream] island_loaded: ", placement.runtime_id)


func _unload_island(runtime_id: StringName) -> void:
	var inst: Node3D = active_islands[runtime_id]
	inst.queue_free()
	active_islands.erase(runtime_id)
	EventBus.island_unloaded.emit(runtime_id)
	print("[WorldStream] island_unloaded: ", runtime_id)


## Completed in Step 14 — wires dropped_item deltas to ItemPickup instances.
func _apply_deltas_to_instance(_instance: Node3D, _placement: IslandPlacement, _deltas: Dictionary) -> void:
	pass


func _update_biome() -> void:
	var new_biome := get_active_biome()
	if new_biome != _last_active_biome:
		_last_active_biome = new_biome
		EventBus.biome_entered.emit(new_biome)


func get_active_biome() -> BiomeDef:
	if _player != null and (not is_instance_valid(_player) or not _player.is_inside_tree()):
		_player = null
	if _player == null:
		return _get_ocean_biome()
	for p in IslandRegistry.placements:
		var placement := p as IslandPlacement
		if _player.global_position.distance_to(placement.position) <= placement.def.footprint_radius:
			return placement.def.biome
	return _get_ocean_biome()


func _get_ocean_biome() -> BiomeDef:
	if _ocean_biome == null:
		_ocean_biome = load(OCEAN_BIOME_PATH)
	return _ocean_biome


func get_delta_store() -> IslandDeltaStore:
	return _delta_store


## Returns the IslandPlacement whose footprint encloses world_pos, else null.
func get_placement_enclosing(world_pos: Vector3) -> IslandPlacement:
	for p in IslandRegistry.placements:
		var placement := p as IslandPlacement
		if world_pos.distance_to(placement.position) <= placement.def.footprint_radius:
			return placement
	return null
