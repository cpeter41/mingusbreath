## Autoload name kept for back-compat. Internals are island-streaming, not chunk-grid streaming. See Phase 5 plan.
##
## Three-tier streaming:
##   Far  — terrain mesh + collider. Loaded once per placement, never unloaded.
##   Mid  — foliage. Loaded when player is near footprint.
##   Near — items, enemies, DeltaRoot. Loaded only when player is on/very close to island.
extends Node

const MID_LOAD_BUFFER_M    := 200.0
const MID_UNLOAD_BUFFER_M  := 280.0
const NEAR_LOAD_BUFFER_M   := 60.0
const NEAR_UNLOAD_BUFFER_M := 100.0
const OCEAN_BIOME_PATH := "res://data/biomes/ocean.tres"

const TIER_FAR  := &"far"
const TIER_MID  := &"mid"
const TIER_NEAR := &"near"

## active_islands[runtime_id] = { "far": Node3D, "mid": Node3D|null, "near": Node3D|null }
var active_islands: Dictionary = {}

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
		_load_far(p as IslandPlacement)
	_first_batch_done = true
	EventBus.world_loaded.emit()
	# Immediately resolve mid/near tiers for the player's spawn position.
	_update_tiers_and_biome()


func _process(_dt: float) -> void:
	if _player != null and (not is_instance_valid(_player) or not _player.is_inside_tree()):
		_player = null
	if _player == null or _container == null or not _first_batch_done:
		return
	_update_tiers_and_biome()


# Walks placements once, doing tier load/unload and biome enclosure in one pass.
func _update_tiers_and_biome() -> void:
	var ppos: Vector3 = _player.global_position
	var enclosing_biome: BiomeDef = null
	for p in IslandRegistry.placements:
		var placement := p as IslandPlacement
		var dist: float = ppos.distance_to(placement.position)
		var fp: float = placement.def.footprint_radius

		if enclosing_biome == null and dist <= fp:
			enclosing_biome = placement.def.biome

		var state: Dictionary = active_islands.get(placement.runtime_id, {})
		if state.is_empty():
			continue

		# Mid tier
		var mid: Node3D = state.get("mid")
		if mid == null and dist <= fp + MID_LOAD_BUFFER_M:
			_load_mid(placement)
		elif mid != null and dist > fp + MID_UNLOAD_BUFFER_M:
			_unload_tier(placement.runtime_id, TIER_MID)

		# Near tier
		var near: Node3D = state.get("near")
		if near == null and dist <= fp + NEAR_LOAD_BUFFER_M:
			_load_near(placement)
		elif near != null and dist > fp + NEAR_UNLOAD_BUFFER_M:
			_unload_tier(placement.runtime_id, TIER_NEAR)

	if enclosing_biome == null:
		enclosing_biome = _get_ocean_biome()
	if enclosing_biome != _last_active_biome:
		_last_active_biome = enclosing_biome
		EventBus.biome_entered.emit(enclosing_biome)


func _load_far(placement: IslandPlacement) -> void:
	var inst: Node3D = placement.def.scene.instantiate()
	inst.position = placement.position
	inst.rotation.y = placement.rotation_y
	_container.add_child(inst)
	active_islands[placement.runtime_id] = {"far": inst, "mid": null, "near": null}
	EventBus.island_loaded.emit(placement, inst)
	EventBus.island_tier_loaded.emit(placement.runtime_id, TIER_FAR, inst)


func _load_mid(placement: IslandPlacement) -> void:
	if placement.def.mid_scene == null:
		return
	var state: Dictionary = active_islands[placement.runtime_id]
	var far_inst: Node3D = state["far"]
	var inst: Node3D = placement.def.mid_scene.instantiate()
	far_inst.add_child(inst)
	state["mid"] = inst
	EventBus.island_tier_loaded.emit(placement.runtime_id, TIER_MID, inst)


func _load_near(placement: IslandPlacement) -> void:
	if placement.def.near_scene == null:
		return
	var state: Dictionary = active_islands[placement.runtime_id]
	var far_inst: Node3D = state["far"]
	var inst: Node3D = placement.def.near_scene.instantiate()
	far_inst.add_child(inst)
	state["near"] = inst
	_apply_near_deltas(inst, placement, _delta_store.get_deltas_for(placement.runtime_id))
	EventBus.island_tier_loaded.emit(placement.runtime_id, TIER_NEAR, inst)


func _unload_tier(runtime_id: StringName, tier: StringName) -> void:
	var state: Dictionary = active_islands.get(runtime_id, {})
	var inst: Node3D = state.get(tier)
	if inst == null:
		return
	inst.queue_free()
	state[tier] = null
	EventBus.island_tier_unloaded.emit(runtime_id, tier)


func _apply_near_deltas(near_root: Node3D, placement: IslandPlacement, deltas: Dictionary) -> void:
	var dropped: Array = deltas.get(&"dropped_item", [])
	if dropped.is_empty():
		return
	var delta_root := near_root.get_node_or_null("DeltaRoot") as Node3D
	if delta_root == null:
		return
	for payload in dropped:
		if typeof(payload) != TYPE_DICTIONARY:
			continue
		var pickup := ItemPickup.new()
		pickup.item_id = StringName(payload.get("item_id", &""))
		pickup.count = int(payload.get("count", 1))
		pickup._source_runtime_id = placement.runtime_id
		pickup._source_payload = payload
		delta_root.add_child(pickup)
		var local_arr: Array = payload.get("local_position", [0.0, 0.0, 0.0])
		pickup.position = V3Codec.decode(local_arr)


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


## Returns the Far tier instance for an island, or null if not loaded.
func get_far_instance(runtime_id: StringName) -> Node3D:
	var state: Dictionary = active_islands.get(runtime_id, {})
	return state.get("far")


## Returns the Near tier's DeltaRoot for an island, or null if Near tier isn't loaded.
func get_delta_root(runtime_id: StringName) -> Node3D:
	var state: Dictionary = active_islands.get(runtime_id, {})
	var near: Node3D = state.get("near")
	if near == null:
		return null
	return near.get_node_or_null("DeltaRoot") as Node3D
