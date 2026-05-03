extends EnemyActionState


func physics_update(_delta: float) -> void:
	if enemy.movementSM.current_state_name() != "chase":
		return
	var player := enemy.get_player()
	if player and enemy.global_position.distance_to(player.global_position) <= enemy.def.attack_range:
		actionSM.transition_to("attack")
