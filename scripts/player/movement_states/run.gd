extends MovementState

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	if not player.is_on_floor():
		movementSM.transition_to("fall")
		return

	if Controls.jump_just_pressed():
		if player.consume_stamina(15.0):
			movementSM.transition_to("jump")
		return

	var dir := _get_move_dir()
	if dir == Vector3.ZERO:
		movementSM.transition_to("idle")
		return

	if Controls.sprint_held() and player.stamina > 0.0:
		movementSM.transition_to("sprint")
		return

	player.velocity.x = dir.x * player.speed
	player.velocity.z = dir.z * player.speed
	SkillManager.add_xp(&"run", delta)
