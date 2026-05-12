class_name Boat
extends CharacterBody3D

const MOUSE_SENSITIVITY := 0.003

@export var max_speed: float = 12.0
@export var accel: float = 1.5            # throttle ramp rate per second (in -1..+1 units)
@export var turn_rate_deg: float = 45.0
@export var water_y: float = 0.0

# Pinned-Y note: setting position.y = water_y after move_and_slide will fight
# the slide if the boat hits a slope. Acceptable here (water is flat).
# Seam to fix when buoyancy + waves land in Phase 8.

var throttle: float = 0.0
var mounted: bool = false
var _player: Node = null
var _mount_rotation_offset: float = 0.0

@onready var _mount_zone: Area3D = $MountZone
@onready var _deck_spawn: Node3D = $DeckSpawn
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	Controls.interact_pressed.connect(_on_interact)
	Controls.mouse_look.connect(_on_mouse_look)


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
	_camera_pivot.rotate_y(-delta.x * MOUSE_SENSITIVITY)
	_spring_arm.rotate_x(-delta.y * MOUSE_SENSITIVITY)
	_spring_arm.rotation.x = clamp(
		_spring_arm.rotation.x, deg_to_rad(-50.0), deg_to_rad(20.0)
	)


func _mount(player: Node) -> void:
	_player = player
	mounted = true
	_mount_rotation_offset = 0.0
	var old_yaw: float = player.rotation.y
	player.rotation.y = rotation.y
	player.global_position = _deck_spawn.global_position
	player.on_boat = true
	_camera_pivot.rotation.y = old_yaw - rotation.y
	_spring_arm.rotation.x = player.camera_pivot.rotation.x
	_camera.make_current()
	Controls.capture_mouse()


func _dismount() -> void:
	if _player != null:
		# Restore player camera angle from boat camera before switching back
		_player.rotation.y = rotation.y + _camera_pivot.rotation.y
		_player.camera_pivot.rotation.x = _spring_arm.rotation.x
		_player.global_position = _deck_spawn.global_position
		_player.velocity = Vector3.ZERO
		_player.on_boat = false
	_camera.clear_current()
	mounted = false
	throttle = 0.0
	_player = null


func _physics_process(delta: float) -> void:
	if not mounted:
		velocity = Vector3.ZERO
		throttle = move_toward(throttle, 0.0, accel * delta)
		return

	var t_in := Controls.throttle_axis()
	var r_in := Controls.rudder_axis()

	throttle = move_toward(throttle, t_in, accel * delta)

	if absf(throttle) > 0.05:
		rotate_y(deg_to_rad(turn_rate_deg) * r_in * delta)

	var fwd := -global_transform.basis.z
	velocity = fwd * throttle * max_speed
	velocity.y = 0.0

	move_and_slide()
	# Soft Y restore: lets terrain push the boat up momentarily so collision response
	# can redirect XZ velocity, instead of being stomped by a hard `position.y = water_y`.
	position.y = lerp(position.y, water_y, 0.4)
	if _player != null:
		_player.global_position = _deck_spawn.global_position
		_player.rotation.y = rotation.y + _mount_rotation_offset
