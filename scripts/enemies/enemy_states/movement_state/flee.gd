extends EnemyMovementState

const FLEE_DURATION  := 5.0
const FLEE_SPEED_MULT := 1.3

var _timer: float = 0.0


func enter() -> void:
	_timer = FLEE_DURATION
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0


func physics_update(delta: float) -> void:
	_apply_gravity(delta)
	_timer -= delta

	var player := enemy.get_player()
	if player:
		var dist := enemy.global_position.distance_to(player.global_position)
		if dist > enemy.def.sense_radius:
			movementSM.transition_to("return")
			return
		var away := (enemy.global_position - player.global_position)
		away.y = 0.0
		if away.length_squared() > 0.001:
			away = away.normalized()
			enemy.velocity.x = away.x * enemy.def.move_speed * FLEE_SPEED_MULT
			enemy.velocity.z = away.z * enemy.def.move_speed * FLEE_SPEED_MULT
	else:
		movementSM.transition_to("return")
		return

	if _timer <= 0.0:
		movementSM.transition_to("return")
