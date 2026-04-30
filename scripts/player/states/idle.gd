extends PlayerState

func physics_update(delta: float) -> void:
	_apply_gravity(delta)
	_decelerate(delta)

	if not player.is_on_floor():
		state_machine.transition_to("fall")
		return

	if Input.is_action_just_pressed("jump"):
		state_machine.transition_to("jump")
		return

	if _get_move_dir() != Vector3.ZERO:
		state_machine.transition_to(
			"sprint" if Input.is_action_pressed("sprint") else "run"
		)


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack_light"):
		state_machine.transition_to("attack")
