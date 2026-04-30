extends MovementState

func physics_update(delta: float) -> void:
	_apply_gravity(delta)
	_decelerate(delta)

	if not player.is_on_floor():
		movementSM.transition_to("fall")
		return

	if Input.is_action_just_pressed("jump"):
		movementSM.transition_to("jump")
		return

	if _get_move_dir() != Vector3.ZERO:
		movementSM.transition_to(
			"sprint" if Input.is_action_pressed("sprint") else "run"
		)
