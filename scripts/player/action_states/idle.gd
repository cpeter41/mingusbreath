extends ActionState

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack_light"):
		actionSM.transition_to("attack")
