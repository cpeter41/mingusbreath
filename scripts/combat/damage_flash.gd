class_name DamageFlash

static var _hit_mat: StandardMaterial3D


static func flash(mesh: MeshInstance3D, duration: float = 0.15) -> void:
	if mesh == null:
		return
	if _hit_mat == null:
		_hit_mat = StandardMaterial3D.new()
		_hit_mat.albedo_color = Color.RED
	mesh.material_override = _hit_mat
	var t := mesh.create_tween()
	t.tween_interval(duration)
	t.tween_callback(func():
		if is_instance_valid(mesh):
			mesh.material_override = null
	)
