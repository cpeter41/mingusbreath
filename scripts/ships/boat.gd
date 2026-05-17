class_name Boat
extends RigidBody3D
# Server-authoritative boat. The host runs the rigid-body physics; transform,
# velocity, throttle and the mounted-peer list replicate to all peers via the
# NetSync MultiplayerSynchronizer. Clients freeze the body and just display the
# replicated transform.
#
# Mounting: a player requests a deck slot via request_mount (routed to the
# server). mounted_peers[0] is the driver and is the only peer whose throttle/
# rudder input the server honours. Mounted players snap themselves to their
# deck slot in Player._physics_process (owner-auth) — the boat does not move
# players directly.

const HULL_COLLIDER_SIZE := Vector3(3.5, 1.4, 8.0)
const MOUNT_RADIUS := 5.5
const DECK_SLOTS := 4

const MAX_THRUST        := 6000.0
const MAX_RUDDER_TORQUE := 8000.0
const RUDDER_MIN_SPEED  := 0.5    # m/s — below this, rudder authority is zero
const RUDDER_FULL_SPEED := 6.0    # m/s — above this, full authority

@export var accel: float = 1.5    # throttle ramp rate per second (-1..+1 units)

# Replicated state.
var throttle: float = 0.0
var mounted_peers: Array = []     # peer ids; index = deck slot, [0] = driver

var _buoyancy: Buoyancy = null
var _drive_throttle: float = 0.0  # latest driver input (server-side only)
var _drive_rudder: float = 0.0

@onready var _deck_slots: Array = [
	$DeckSpawn0, $DeckSpawn1, $DeckSpawn2, $DeckSpawn3
]


func _ready() -> void:
	add_to_group("boat")
	mass = 500.0
	linear_damp = 1.5
	angular_damp = 5.0
	gravity_scale = 1.0
	can_sleep = false
	collision_mask = 9  # layer 1 (terrain) + layer 8 (shore wall)
	if multiplayer.is_server():
		_setup_buoyancy()
	else:
		# Clients: physics runs on the host; display the replicated transform.
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _setup_buoyancy() -> void:
	_buoyancy = Buoyancy.new()
	_buoyancy.hull_points = [
		Vector3(-1.75, -0.7, -4.0),
		Vector3( 1.75, -0.7, -4.0),
		Vector3(-1.75, -0.7,  4.0),
		Vector3( 1.75, -0.7,  4.0),
	]
	_buoyancy.per_point_max_force = (mass * 9.81 / 4.0) * 2.0
	_buoyancy.submersion_scale = HULL_COLLIDER_SIZE.y * 0.5
	add_child(_buoyancy)


## World transform of a deck slot. Mounted players snap themselves here.
func deck_slot_transform(slot: int) -> Transform3D:
	slot = clampi(slot, 0, DECK_SLOTS - 1)
	return (_deck_slots[slot] as Node3D).global_transform


func slot_of(peer_id: int) -> int:
	return mounted_peers.find(peer_id)


func is_driver(peer_id: int) -> bool:
	return mounted_peers.size() > 0 and mounted_peers[0] == peer_id


# ── Mount / dismount (server-authoritative) ──────────────────────
# call_local + a server guard: a guest's rpc_id(1, ...) also runs locally but
# returns at the guard; the host's own call runs once on the server.

@rpc("any_peer", "reliable", "call_local")
func request_mount(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id in mounted_peers or mounted_peers.size() >= DECK_SLOTS:
		return
	var pnode := _find_player(peer_id)
	if pnode == null or pnode.global_position.distance_to(global_position) > MOUNT_RADIUS:
		return
	mounted_peers.append(peer_id)


@rpc("any_peer", "reliable", "call_local")
func request_dismount(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	mounted_peers.erase(peer_id)


## Driver input. Host driver calls this directly; guest driver routes via RPC.
func submit_drive(t: float, r: float) -> void:
	if multiplayer.is_server():
		_apply_drive(multiplayer.get_unique_id(), t, r)
	else:
		_drive_rpc.rpc_id(1, t, r)


@rpc("any_peer", "unreliable_ordered")
func _drive_rpc(t: float, r: float) -> void:
	if not multiplayer.is_server():
		return
	_apply_drive(multiplayer.get_remote_sender_id(), t, r)


func _apply_drive(sender_id: int, t: float, r: float) -> void:
	if not is_driver(sender_id):
		return  # only the driver steers
	_drive_throttle = clampf(t, -1.0, 1.0)
	_drive_rudder = clampf(r, -1.0, 1.0)


func _find_player(peer_id: int) -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var players := scene.get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null("Player_%d" % peer_id) as Node3D


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return  # clients receive transform via the synchronizer
	if mounted_peers.is_empty():
		throttle = move_toward(throttle, 0.0, accel * delta)
		_drive_throttle = 0.0
		_drive_rudder = 0.0
	else:
		throttle = move_toward(throttle, _drive_throttle, accel * delta)

	var fwd := -global_transform.basis.z
	apply_central_force(fwd * throttle * MAX_THRUST)

	var fwd_speed := absf(linear_velocity.dot(fwd))
	var rudder_authority := clampf(
		(fwd_speed - RUDDER_MIN_SPEED) / (RUDDER_FULL_SPEED - RUDDER_MIN_SPEED),
		0.0, 1.0
	)
	apply_torque(Vector3.UP * (_drive_rudder * MAX_RUDDER_TORQUE * rudder_authority))
