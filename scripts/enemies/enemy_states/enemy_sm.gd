class_name EnemyMovementSM
extends StateMachine


func _ready() -> void:
	var enemy := owner as Enemy
	for child in get_children():
		if child is EnemyMovementState:
			_states[child.name.to_lower()] = child
			child.enemy = enemy
			child.movementSM = self
	# Deferred so all child state nodes finish _ready before any state.enter() runs.
	transition_to.call_deferred("idle")
