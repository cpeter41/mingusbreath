extends MovementState

func physics_update(delta: float) -> void:
	_apply_gravity(delta)
	_decelerate(delta)

	if not player.is_on_floor():
		movementSM.transition_to("fall")
		return

	if Controls.jump_just_pressed():
		if player.consume_stamina(15.0):
			movementSM.transition_to("jump")
		return

	if _get_move_dir() != Vector3.ZERO:
		movementSM.transition_to(
			"sprint" if Controls.sprint_held() else "run"
		)
