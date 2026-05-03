class_name ActionSM
extends StateMachine


func _ready() -> void:
	var player := owner as CharacterBody3D
	for child in get_children():
		if child is ActionState:
			_states[child.name.to_lower()] = child
			child.player = player
			child.actionSM = self
	transition_to.call_deferred("idle")
