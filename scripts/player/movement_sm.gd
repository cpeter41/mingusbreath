class_name MovementSM
extends StateMachine


func _ready() -> void:
	var player := owner as CharacterBody3D
	for child in get_children():
		if child is MovementState:
			_states[child.name.to_lower()] = child
			child.player = player
			child.movementSM = self
	# Deferred so all child state nodes finish _ready before any state.enter() runs.
	transition_to.call_deferred("fall")


## Push the new state name to the owner so its replicated `anim_state` setter
## fires the matching clip on every peer. Only ticks on the authority since
## non-owners have physics_process disabled.
func transition_to(state_name: String) -> void:
	super.transition_to(state_name)
	if _current == null:
		return
	var p := owner
	if p != null and p.is_multiplayer_authority():
		p.set(&"anim_state", StringName(_current.name.to_lower()))
