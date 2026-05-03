class_name MovementSM
extends StateMachine


func _ready() -> void:
	var player := owner as CharacterBody3D
	for child in get_children():
		if child is MovementState:
			_states[child.name.to_lower()] = child
			child.player = player
			child.movementSM = self
	transition_to.call_deferred("fall")
