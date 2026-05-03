extends EnemyMovementState

const LOSE_INTEREST_MULT := 1.5

func enter() -> void:
	pass


func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var player := enemy.get_player()
	if not player:
		movementSM.transition_to("return")
		return

	var dist := enemy.global_position.distance_to(player.global_position)

	# Lost player — too far beyond sense radius
	if dist > enemy.def.sense_radius * LOSE_INTEREST_MULT:
		movementSM.transition_to("return")
		return

	var dir := (player.global_position - enemy.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	enemy.velocity.x = dir.x * enemy.def.move_speed
	enemy.velocity.z = dir.z * enemy.def.move_speed
