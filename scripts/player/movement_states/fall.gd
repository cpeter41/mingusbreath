extends MovementState

const SPEED     := 5.0
const AIR_ACCEL := 10.0	# consider moving this to a global

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var dir := _get_move_dir()
	if dir != Vector3.ZERO:
		player.velocity.x = move_toward(player.velocity.x, dir.x * SPEED, AIR_ACCEL * delta)
		player.velocity.z = move_toward(player.velocity.z, dir.z * SPEED, AIR_ACCEL * delta)

	if player.is_on_floor():
		movementSM.transition_to(
			"sprint" if Controls.sprint_held() and _get_move_dir() != Vector3.ZERO
			else "run" if _get_move_dir() != Vector3.ZERO
			else "idle"
		)
