class_name EnemyActionState
extends BaseState

var enemy: Enemy
var actionSM: StateMachine  # concrete type causes circular ref

var _mesh_tween: Tween


func _lean_mesh(target_deg: float, duration: float) -> void:
	if enemy.mesh == null:
		return
	if _mesh_tween:
		_mesh_tween.kill()
	_mesh_tween = enemy.create_tween()
	_mesh_tween.tween_property(enemy.mesh, "rotation:x", deg_to_rad(target_deg), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _reset_mesh_lean() -> void:
	if _mesh_tween:
		_mesh_tween.kill()
	if enemy.mesh != null:
		enemy.mesh.rotation.x = 0.0
