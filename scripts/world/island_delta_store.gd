class_name IslandDeltaStore
extends Node

# _deltas[runtime_id][type] = Array of payload Dictionaries
var _deltas: Dictionary = {}


func _ready() -> void:
	SaveSystem.register(self)


func add_delta(runtime_id: StringName, type: StringName, payload: Dictionary) -> void:
	if not _deltas.has(runtime_id):
		_deltas[runtime_id] = {}
	if not _deltas[runtime_id].has(type):
		_deltas[runtime_id][type] = []
	_deltas[runtime_id][type].append(payload)


func get_deltas_for(runtime_id: StringName) -> Dictionary:
	return _deltas.get(runtime_id, {})


## Removes first payload entry whose contents == match. Returns true if found.
func remove_delta_match(runtime_id: StringName, type: StringName, payload: Dictionary) -> bool:
	if not _deltas.has(runtime_id):
		return false
	if not _deltas[runtime_id].has(type):
		return false
	var arr: Array = _deltas[runtime_id][type]
	for i in arr.size():
		if arr[i] == payload:
			arr.remove_at(i)
			return true
	return false


func clear_island(runtime_id: StringName) -> void:
	_deltas.erase(runtime_id)


func save_data() -> Dictionary:
	return {"deltas": _freeze(_deltas)}


func load_data(d: Dictionary) -> void:
	_deltas = _thaw(d.get("deltas", {}))


## Convert StringName keys → String for serialisation.
func _freeze(src: Dictionary) -> Dictionary:
	var out := {}
	for rid in src:
		var by_type := {}
		for t in src[rid]:
			by_type[String(t)] = src[rid][t].duplicate(true)
		out[String(rid)] = by_type
	return out


## Convert String keys back → StringName after deserialisation.
func _thaw(src: Dictionary) -> Dictionary:
	var out := {}
	for rid in src:
		var by_type := {}
		for t in src[rid]:
			by_type[StringName(t)] = src[rid][t].duplicate(true)
		out[StringName(rid)] = by_type
	return out
