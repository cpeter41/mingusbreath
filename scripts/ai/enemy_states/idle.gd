extends EnemyMovementState

var _timer: float = 0.0
const WAIT_TIME := 1.5


func enter() -> void:
	_timer = WAIT_TIME


func physics_update(delta: float) -> void:
	_apply_gravity(delta)
	_timer -= delta
	if _timer <= 0.0:
		movementSM.transition_to("patrol")
