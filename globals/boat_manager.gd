extends Node
# Host-owned boat registry. Boats are server-authoritative and spawn into
# /World/Boats via the BoatSpawner MultiplayerSpawner, so the host adding a
# boat there replicates it to every peer.

const BOAT_SCENE := preload("res://scenes/ships/Boat.tscn")
# Must match BoatSpawner.spawn_limit in World.tscn; exceeding it silently
# drops replication on clients.
const BOAT_SPAWN_LIMIT := 8

var _boats: Array[Boat] = []
var _pending: Array = []


func _ready() -> void:
	SaveSystem.register(self)
	EventBus.world_loaded.connect(_on_world_loaded)


func register_boat(boat: Boat) -> void:
	if boat not in _boats:
		_boats.append(boat)


## Returns this owner's boat, or null if they don't have one yet.
func get_boat_for_owner(owner_peer_id: int) -> Boat:
	for b in _boats:
		if is_instance_valid(b) and b.is_inside_tree() and b.owner_peer_id == owner_peer_id:
			return b
	return null


## Player-facing entry. Routed to the host; guests' calls run there too.
## owner_peer_id tags the boat so each player can only move their own.
@rpc("any_peer", "reliable", "call_local")
func request_spawn_boat(pos: Vector3, rot_y: float, owner_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var existing := get_boat_for_owner(owner_peer_id)
	if existing != null:
		# Boat already exists for this player — just reposition it.
		existing.global_position = pos
		existing.rotation.y = rot_y
		return
	_spawn_boat(pos, rot_y, Vector3.ZERO, Vector3.ZERO, owner_peer_id)


## When a player's peer_id is now known, match any saved boat whose stable_owner_id
## lines up so it gets an owner_peer_id for the current session.
func assign_owner_peer_from_stable_id(stable_id: String, peer_id: int) -> void:
	if stable_id.is_empty():
		return
	for b in _boats:
		if is_instance_valid(b) and b.stable_owner_id == stable_id and b.owner_peer_id == 0:
			b.owner_peer_id = peer_id


func _boats_container() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Boats")


func _spawn_boat(
	pos: Vector3,
	rot_y: float,
	lin_vel: Vector3,
	ang_vel: Vector3,
	owner_peer_id: int = 0,
) -> Boat:
	var boats := _boats_container()
	if boats == null:
		push_warning("[BoatManager] /World/Boats container missing")
		return null
	# Enforce spawn_limit so the 9th boat doesn't silently orphan itself on the host.
	if _boats.size() >= BOAT_SPAWN_LIMIT:
		push_warning("[BoatManager] boat spawn_limit (%d) reached; ignoring spawn" % BOAT_SPAWN_LIMIT)
		return null
	var boat := BOAT_SCENE.instantiate() as Boat
	boat.rotation.y = rot_y
	# Set owner before add_child so the synchronizer replicates it on spawn.
	boat.owner_peer_id = owner_peer_id
	if owner_peer_id != 0:
		boat.stable_owner_id = NetworkManager.get_stable_id(owner_peer_id)
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
			# stable_owner_id persists across sessions; owner_peer_id is session-only.
			"stable_owner_id": boat.stable_owner_id,
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
		# owner_peer_id starts at 0; assign_owner_peer_from_stable_id resolves it
		# once players connect and their stable_id is known.
		var boat := _spawn_boat(
			V3Codec.decode(bd["position"]),
			float(bd.get("rotation_y", 0.0)),
			V3Codec.decode(bd["linear_velocity"]) if bd.has("linear_velocity") else Vector3.ZERO,
			V3Codec.decode(bd["angular_velocity"]) if bd.has("angular_velocity") else Vector3.ZERO,
		)
		if boat != null:
			boat.stable_owner_id = bd.get("stable_owner_id", "")
	_pending.clear()
