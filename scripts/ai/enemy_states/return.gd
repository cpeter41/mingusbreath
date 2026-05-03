extends EnemyMovementState

const ARRIVE_THRESHOLD := 1.5


func enter() -> void:
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0


func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var player := enemy.get_player()
	if player and enemy.global_position.distance_to(player.global_position) <= enemy.def.sense_radius:
		movementSM.transition_to("sense")
		return

	var to_anchor := enemy.spawn_anchor - enemy.global_position
	to_anchor.y = 0.0

	if to_anchor.length() < ARRIVE_THRESHOLD:
		movementSM.transition_to("idle")
		return

	var dir := to_anchor.normalized()
	enemy.velocity.x = dir.x * enemy.def.move_speed * 0.5
	enemy.velocity.z = dir.z * enemy.def.move_speed * 0.5
