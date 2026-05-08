extends ActionState

# physics_update instead of handle_input to allow for holding attack/block button
func physics_update(_delta: float) -> void:
	if not player.on_boat and Controls.dodge_just_pressed():
		if player.consume_stamina(20.0):
			actionSM.transition_to("dodge")
		return
	if not player.on_boat and Controls.block_held() and player.has_shield():
		actionSM.transition_to("block")
		return
	if not player.on_boat and Controls.attack_light_held():
		if player.weapon_mount.get_node_or_null("Sword") != null:
			if player.consume_stamina(10.0):
				actionSM.transition_to("attack")
