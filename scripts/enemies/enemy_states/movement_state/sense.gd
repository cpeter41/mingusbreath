extends EnemyMovementState

var _timer: float = 0.0
const ALERT_TIME := 0.5

func enter() -> void:
	_timer = ALERT_TIME
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0


func physics_update(delta: float) -> void:
	_apply_gravity(delta)
	_timer -= delta
	if _timer <= 0.0:
		var player := enemy.get_player()
		if player and enemy.global_position.distance_to(player.global_position) <= enemy.def.sense_radius:
			movementSM.transition_to("chase")
		else:
			movementSM.transition_to("patrol")
