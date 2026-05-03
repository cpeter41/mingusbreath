extends EnemyMovementState

const LOSE_INTEREST_MULT := 1.5

func enter() -> void:
	pass


func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var player := enemy.get_player()
	if not player:
		movementSM.transition_to("return")
		return

	var dist := enemy.global_position.distance_to(player.global_position)

	# Lost player — too far beyond sense radius
	if dist > enemy.def.sense_radius * LOSE_INTEREST_MULT:
		movementSM.transition_to("return")
		return

	var dir := (player.global_position - enemy.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	enemy.velocity.x = dir.x * enemy.def.move_speed
	enemy.velocity.z = dir.z * enemy.def.move_speed
	_face_dir(dir)


func _face_dir(dir: Vector3) -> void:
	if dir.length_squared() < 0.001:
		return
	var flat_target := enemy.global_position + dir
	flat_target.y = enemy.global_position.y
	enemy.look_at(flat_target, Vector3.UP)
