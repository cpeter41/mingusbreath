class_name Boat
extends CharacterBody3D

const HULL_VISUAL_SIZE   := Vector3(2.0, 0.6, 5.0)
const HULL_COLLIDER_SIZE := Vector3(2.0, 1.4, 5.0)
const MOUNT_RADIUS := 3.5
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

var _hull_mesh: MeshInstance3D
var _mount_zone: Area3D
var _deck_spawn: Node3D
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D

func _ready() -> void:
	collision_mask = 9  # layer 1 (terrain) + layer 8 (shore wall)
	_build_hull()
	_build_deck_spawn()
	_build_mount_zone()
	_build_camera_rig()
	Controls.interact_pressed.connect(_on_interact)
	Controls.mouse_look.connect(_on_mouse_look)

func _build_hull() -> void:
	_hull_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = HULL_VISUAL_SIZE
	_hull_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.27, 0.14)
	_hull_mesh.material_override = mat
	add_child(_hull_mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = HULL_COLLIDER_SIZE
	col.shape = shape
	# Drop collider so its top stays flush with the visual hull — extra depth hangs below the waterline.
	col.position.y = (HULL_VISUAL_SIZE.y - HULL_COLLIDER_SIZE.y) * 0.5
	add_child(col)

func _build_deck_spawn() -> void:
	_deck_spawn = Node3D.new()
	_deck_spawn.name = "DeckSpawn"
	_deck_spawn.position = Vector3(0.0, HULL_VISUAL_SIZE.y * 0.5 + 0.0, 0.0)  # top-center of hull
	add_child(_deck_spawn)

func _build_mount_zone() -> void:
	_mount_zone = Area3D.new()
	_mount_zone.collision_layer = 0
	_mount_zone.collision_mask = 1   # detect player on default layer 1
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = MOUNT_RADIUS
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	_mount_zone.add_child(col)
	add_child(_mount_zone)

func _build_camera_rig() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0, 1.6, 0)
	add_child(_camera_pivot)

	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 8.0
	_spring_arm.collision_mask = 1
	_camera_pivot.add_child(_spring_arm)

	_camera = Camera3D.new()
	_camera.current = false
	_spring_arm.add_child(_camera)

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
	_camera.current = true
	Controls.capture_mouse()

func _dismount() -> void:
	if _player != null:
		# Restore player camera angle from boat camera before switching back
		_player.rotation.y = rotation.y + _camera_pivot.rotation.y
		_player.camera_pivot.rotation.x = _spring_arm.rotation.x
		_player.global_position = _deck_spawn.global_position
		_player.velocity = Vector3.ZERO
		_player.on_boat = false
	_camera.current = false
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
