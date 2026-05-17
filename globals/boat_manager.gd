extends Node
# Host-owned boat registry. Boats are server-authoritative and spawn into
# /World/Boats via the BoatSpawner MultiplayerSpawner, so the host adding a
# boat there replicates it to every peer.

const BOAT_SCENE := preload("res://scenes/ships/Boat.tscn")

var _boats: Array[Boat] = []
var _pending: Array = []


func _ready() -> void:
	SaveSystem.register(self)
	EventBus.world_loaded.connect(_on_world_loaded)


func register_boat(boat: Boat) -> void:
	if boat not in _boats:
		_boats.append(boat)


func get_existing_boat() -> Boat:
	for b in _boats:
		if is_instance_valid(b) and b.is_inside_tree():
			return b
	return null


## Player-facing entry. Routed to the host; guests' calls run there too.
@rpc("any_peer", "reliable", "call_local")
func request_spawn_boat(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	var existing := get_existing_boat()
	if existing != null:
		existing.global_position = pos
		existing.rotation.y = rot_y
		return
	_spawn_boat(pos, rot_y, Vector3.ZERO, Vector3.ZERO)


func _boats_container() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Boats")


func _spawn_boat(pos: Vector3, rot_y: float, lin_vel: Vector3, ang_vel: Vector3) -> Boat:
	var boats := _boats_container()
	if boats == null:
		push_warning("[BoatManager] /World/Boats container missing")
		return null
	var boat := BOAT_SCENE.instantiate() as Boat
	boat.rotation.y = rot_y
	boats.add_child(boat, true)
	boat.global_position = pos
	boat.linear_velocity = lin_vel
	boat.angular_velocity = ang_vel
	register_boat(boat)
	return boat


func save_data() -> Dictionary:
	var out: Array = []
	for boat in _boats:
		if not is_instance_valid(boat):
			continue
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
	# Only the host spawns boats; the BoatSpawner replicates them to guests.
	if not multiplayer.is_server():
		return
	for bd in _pending:
		_spawn_boat(
			V3Codec.decode(bd["position"]),
			float(bd.get("rotation_y", 0.0)),
			V3Codec.decode(bd["linear_velocity"]) if bd.has("linear_velocity") else Vector3.ZERO,
			V3Codec.decode(bd["angular_velocity"]) if bd.has("angular_velocity") else Vector3.ZERO,
		)
	_pending.clear()
