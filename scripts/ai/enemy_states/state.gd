class_name EnemyMovementState
extends BaseState

var enemy: Enemy
var movementSM: StateMachine  # concrete type causes circular ref


func _apply_gravity(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy.velocity.y -= enemy.gravity * delta
