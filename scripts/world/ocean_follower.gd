class_name OceanFollower
extends Node3D

var _target: Node3D = null


func set_target(node: Node3D) -> void:
	_target = node
	var mesh := $WaterMesh as MeshInstance3D
	Ocean.set_water_material(mesh.material_override as ShaderMaterial)


func _exit_tree() -> void:
	Ocean.set_water_material(null)


func _process(_dt: float) -> void:
	if _target == null:
		return
	var t := _target.global_position
	global_position = Vector3(t.x, Ocean.WATER_BASE_Y, t.z)
