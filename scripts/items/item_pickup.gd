class_name ItemPickup
extends Area3D

@export var item_id: StringName = &""
@export var count: int = 1

var _target: Node3D = null
var _chase_speed: float = 4.0
var _source_runtime_id: StringName = &""
var _source_payload: Dictionary = {}

func _ready() -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.7, 0.2)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.6
	add_child(col)
	collision_layer = 8
	collision_mask = 1

	body_entered.connect(_on_body_entered)


func spring(origin: Vector3) -> void:
	global_position = origin
	monitoring = false

	var angle := randf() * TAU
	var dist  := randf_range(0.5, 1.2)
	var land  := Vector3(
		origin.x + cos(angle) * dist,
		origin.y - 0.35,
		origin.z + sin(angle) * dist
	)

	var xz := create_tween().set_parallel(true)
	xz.tween_property(self, "global_position:x", land.x, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	xz.tween_property(self, "global_position:z", land.z, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var y := create_tween()
	y.tween_property(self, "global_position:y", origin.y + 0.7, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	y.tween_property(self, "global_position:y", land.y, 0.17) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	y.tween_callback(func(): monitoring = true).set_delay(0.2)


func _process(delta: float) -> void:
	if _target == null:
		return
	if not is_instance_valid(_target):
		queue_free()
		return
	_chase_speed += 18.0 * delta
	var destination := _target.global_position + Vector3.UP * 0.9
	var dir := (destination - global_position).normalized()
	global_position += dir * _chase_speed * delta
	if global_position.distance_to(destination) < 0.2:
		_target.take_pickup(item_id, count)
		if _source_runtime_id != &"":
			WorldStream.get_delta_store().remove_delta_match(_source_runtime_id, &"dropped_item", _source_payload)
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_pickup") and _target == null:
		set_deferred("monitoring", false)
		_target = body
