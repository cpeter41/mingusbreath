extends EnemyActionState

const STAGGER_TIME := 1.5

var _timer: float = 0.0
var _mesh_tween: Tween


func enter() -> void:
	_timer = STAGGER_TIME
	_lean_mesh(10.0, 0.2)


func physics_update(delta: float) -> void:
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	_timer -= delta
	if _timer <= 0.0:
		actionSM.transition_to("idle")


func exit() -> void:
	if _mesh_tween:
		_mesh_tween.kill()
	var mesh := enemy.get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.rotation.x = 0.0


func _lean_mesh(target_deg: float, duration: float) -> void:
	var mesh := enemy.get_node_or_null("Mesh") as MeshInstance3D
	if not mesh:
		return
	if _mesh_tween:
		_mesh_tween.kill()
	_mesh_tween = enemy.create_tween()
	_mesh_tween.tween_property(mesh, "rotation:x", deg_to_rad(target_deg), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
