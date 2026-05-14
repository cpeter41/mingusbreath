class_name Boat
extends RigidBody3D

const HULL_VISUAL_SIZE   := Vector3(3.5, 0.6, 8.0)
const HULL_COLLIDER_SIZE := Vector3(3.5, 1.4, 8.0)
const MOUNT_RADIUS := 5.5
const MOUSE_SENSITIVITY := 0.003

const MAX_THRUST        := 6000.0
const MAX_RUDDER_TORQUE := 8000.0
const RUDDER_MIN_SPEED  := 0.5    # m/s — below this, rudder authority is zero
const RUDDER_FULL_SPEED := 6.0    # m/s — above this, full authority

@export var accel: float = 1.5    # throttle ramp rate per second (in -1..+1 units)

var throttle: float = 0.0
var mounted: bool = false
var _player: Node = null
var _yaw_input: float = 0.0       # accumulated mouse yaw, world-relative offset from boat heading
var _buoyancy: Buoyancy = null
var _player_col_layer: int = 0
var _player_col_mask: int = 0

@onready var _mount_zone: Area3D = $MountZone
@onready var _deck_spawn: Node3D = $DeckSpawn
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	mass = 500.0
	linear_damp = 1.5
	angular_damp = 5.0
	gravity_scale = 1.0
	can_sleep = false
	collision_mask = 9  # layer 1 (terrain) + layer 8 (shore wall)
	_setup_buoyancy()
	Controls.interact_pressed.connect(_on_interact)
	Controls.mouse_look.connect(_on_mouse_look)


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

func _on_interact() -> void:
	if mounted:
		_dismount()
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and _mount_zone.overlaps_body(player) and player.is_on_floor():
		_mount(player)

func _on_mouse_look(delta: Vector2) -> void:
	if not mounted:
		return
	_yaw_input -= delta.x * MOUSE_SENSITIVITY
	_spring_arm.rotate_x(-delta.y * MOUSE_SENSITIVITY)
	_spring_arm.rotation.x = clamp(
		_spring_arm.rotation.x, deg_to_rad(-50.0), deg_to_rad(20.0)
	)

func _process(_delta: float) -> void:
	if not mounted:
		return
	# Override pivot's inherited transform so camera yaws with boat heading + mouse, never rolls.
	_camera_pivot.global_position = global_position + Vector3(0, 1.6, 0)
	_camera_pivot.global_rotation = Vector3(0, global_rotation.y + _yaw_input, 0)

func _mount(player: Node) -> void:
	_player = player
	mounted = true
	_yaw_input = 0.0
	_player_col_layer = player.collision_layer
	_player_col_mask  = player.collision_mask
	player.collision_layer = 0
	player.collision_mask  = 0
	player.global_transform = _deck_spawn.global_transform
	player.on_boat = true
	_camera_pivot.global_rotation = Vector3(0, global_rotation.y, 0)
	_spring_arm.rotation.x = player.camera_pivot.rotation.x
	_camera.make_current()
	Controls.capture_mouse()


func _dismount() -> void:
	if _player != null:
		_player.global_position = _deck_spawn.global_position
		_player.global_rotation = Vector3(0, global_rotation.y + _yaw_input, 0)
		_player.camera_pivot.rotation.x = _spring_arm.rotation.x
		_player.collision_layer = _player_col_layer
		_player.collision_mask  = _player_col_mask
		_player.velocity = Vector3.ZERO
		_player.on_boat = false
	_camera.clear_current()
	mounted = false
	throttle = 0.0
	_player = null


func _physics_process(delta: float) -> void:
	if not mounted:
		throttle = move_toward(throttle, 0.0, accel * delta)
		return

	var t_in := Controls.throttle_axis()
	var r_in := Controls.rudder_axis()
	throttle = move_toward(throttle, t_in, accel * delta)

	var fwd := -global_transform.basis.z
	apply_central_force(fwd * throttle * MAX_THRUST)

	var fwd_speed := absf(linear_velocity.dot(fwd))
	var rudder_authority := clampf(
		(fwd_speed - RUDDER_MIN_SPEED) / (RUDDER_FULL_SPEED - RUDDER_MIN_SPEED),
		0.0, 1.0
	)
	apply_torque(Vector3.UP * (r_in * MAX_RUDDER_TORQUE * rudder_authority))

	if mounted and _player != null:
		_player.global_transform = _deck_spawn.global_transform
		_player.velocity = Vector3.ZERO
