class_name OceanFollower
extends Node3D

const WATER_Y := -0.15

var _target: Node3D = null


func set_target(node: Node3D) -> void:
	_target = node


func _process(_dt: float) -> void:
	if _target == null:
		return
	global_position = Vector3(_target.global_position.x, WATER_Y, _target.global_position.z)
