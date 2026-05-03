class_name EnemyMovementSM
extends StateMachine


func _ready() -> void:
	var enemy := owner as Enemy
	for child in get_children():
		if child is EnemyMovementState:
			_states[child.name.to_lower()] = child
			child.enemy = enemy
			child.movementSM = self
	transition_to.call_deferred("idle")
