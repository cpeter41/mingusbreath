class_name EnemyActionSM
extends StateMachine


func _ready() -> void:
	var enemy := owner as Enemy
	for child in get_children():
		if child is EnemyActionState:
			_states[child.name.to_lower()] = child
			child.enemy = enemy
			child.actionSM = self
	transition_to.call_deferred("idle")
