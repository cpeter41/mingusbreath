extends Node

var _boats: Array[Boat] = []
var _pending: Array = []


func _ready() -> void:
	SaveSystem.register(self)
	EventBus.world_loaded.connect(_on_world_loaded)


func register_boat(boat: Boat) -> void:
	_boats.append(boat)


func save_data() -> Dictionary:
	var out: Array = []
	for boat in _boats:
		if not is_instance_valid(boat):
			continue
		# boat.position (local) used because global_position requires is_inside_tree(),
		# which is already false during scene teardown. WorldRoot has no transform so local == world.
		out.append({
			"position": V3Codec.encode(boat.position),
			"rotation_y": boat.rotation.y,
			"linear_velocity": V3Codec.encode(boat.linear_velocity),
			"angular_velocity": V3Codec.encode(boat.angular_velocity),
		})
	return {"boats": out}


func load_data(d: Dictionary) -> void:
	_pending = d.get("boats", [])


func _on_world_loaded() -> void:
	_boats.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	for bd in _pending:
		var boat := Boat.new()
		boat.rotation.y = float(bd.get("rotation_y", 0.0))
		scene.add_child(boat)
		boat.global_position = V3Codec.decode(bd["position"])
		if bd.has("linear_velocity"):
			boat.linear_velocity = V3Codec.decode(bd["linear_velocity"])
		if bd.has("angular_velocity"):
			boat.angular_velocity = V3Codec.decode(bd["angular_velocity"])
		register_boat(boat)
	_pending.clear()
