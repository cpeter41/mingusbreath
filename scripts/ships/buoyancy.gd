class_name Buoyancy
extends Node3D

@export var hull_points: Array[Vector3] = []
@export var per_point_max_force: float = 1000.0
@export var submersion_scale: float = 0.5
@export var per_point_linear_drag: float = 0.0  # off by default; enables wave-push when > 0

var _body: RigidBody3D = null

func _ready() -> void:
	_body = get_parent() as RigidBody3D
	assert(_body != null, "Buoyancy must be a child of a RigidBody3D")

func _physics_process(_delta: float) -> void:
	if _body == null:
		return
	var t := _body.global_transform
	for local_point: Vector3 in hull_points:
		var world_point := t * local_point
		var surface_y := Ocean.get_height(world_point.x, world_point.z, Ocean.time)
		var depth := surface_y - world_point.y
		if depth <= 0.0:
			continue
		var submersion := clampf(depth / submersion_scale, 0.0, 1.0)
		var offset := world_point - _body.global_position
		_body.apply_force(Vector3(0.0, per_point_max_force * submersion, 0.0), offset)
		if per_point_linear_drag > 0.0:
			var pv := _body.linear_velocity + _body.angular_velocity.cross(offset)
			var horiz := Vector3(pv.x, 0.0, pv.z)
			_body.apply_force(-horiz * per_point_linear_drag * submersion, offset)
