extends ActionState

# physics_update instead of handle_input to allow for holding attack button
func physics_update(_delta: float) -> void:
	if not player.on_boat and Input.is_action_pressed("attack_light"):
		if player.weapon_mount.get_node_or_null("Sword") != null:
			actionSM.transition_to("attack")
