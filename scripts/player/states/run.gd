extends PlayerState

const SPEED := 5.0

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	if not player.is_on_floor():
		state_machine.transition_to("fall")
		return

	if Input.is_action_just_pressed("jump"):
		state_machine.transition_to("jump")
		return

	var dir := _get_move_dir()
	if dir == Vector3.ZERO:
		state_machine.transition_to("idle")
		return

	if Input.is_action_pressed("sprint"):
		state_machine.transition_to("sprint")
		return

	player.velocity.x = dir.x * SPEED
	player.velocity.z = dir.z * SPEED
	SkillManager.add_xp(&"run", delta)


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack_light"):
		state_machine.transition_to("attack")
