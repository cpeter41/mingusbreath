class_name WorldBorder
extends Node3D

var _material: ShaderMaterial = null
var _player: Node3D = null


func _ready() -> void:
	var mi := find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi != null:
		_material = mi.material_override as ShaderMaterial


func _process(_dt: float) -> void:
	if _material == null:
		return
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_material.set_shader_parameter("player_pos", _player.global_position)
