extends EnemyActionState

const STAGGER_TIME := 1.5

var _timer: float = 0.0


func enter() -> void:
	_timer = STAGGER_TIME
	_lean_mesh(10.0, 0.2)


func physics_update(delta: float) -> void:
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	_timer -= delta
	if _timer <= 0.0:
		actionSM.transition_to("idle")


func exit() -> void:
	_reset_mesh_lean()
