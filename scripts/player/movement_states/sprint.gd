extends MovementState

const SPEED_MULTIPLIER := 1.4

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	if not player.is_on_floor():
		movementSM.transition_to("fall")
		return

	if Input.is_action_just_pressed("jump"):
		movementSM.transition_to("jump")
		return

	var dir := _get_move_dir()
	if dir == Vector3.ZERO:
		movementSM.transition_to("idle")
		return

	if not Input.is_action_pressed("sprint"):
		movementSM.transition_to("run")
		return

	player.velocity.x = dir.x * player.speed * SPEED_MULTIPLIER
	player.velocity.z = dir.z * player.speed * SPEED_MULTIPLIER
	SkillManager.add_xp(&"run", delta * 1.5)
