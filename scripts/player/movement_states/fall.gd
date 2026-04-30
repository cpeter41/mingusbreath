extends MovementState

const SPEED := 5.0

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var dir := _get_move_dir()
	if dir != Vector3.ZERO:
		player.velocity.x = dir.x * SPEED
		player.velocity.z = dir.z * SPEED

	if player.is_on_floor():
		movementSM.transition_to(
			"sprint" if Input.is_action_pressed("sprint") and _get_move_dir() != Vector3.ZERO
			else "run" if _get_move_dir() != Vector3.ZERO
			else "idle"
		)
