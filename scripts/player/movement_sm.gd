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
	_push_anim()


## Re-asserts the current locomotion clip. Called by the attack action-state
## (via action `idle`) when a swing ends, so the animation channel returns to
## movement without waiting for the next locomotion transition.
func reassert_anim() -> void:
	_push_anim()


## Writes the current movement state name to the owner's replicated `anim_state`.
## Skipped while an action state with its own clip (attack/dodge) owns the
## animation channel so a locomotion transition can't clobber that clip.
const _ANIM_ACTION_STATES := ["attack", "dodge"]

func _push_anim() -> void:
	if _current == null:
		return
	var p := owner
	if p == null or not p.is_multiplayer_authority():
		return
	if p.actionSM != null and p.actionSM.current_state_name() in _ANIM_ACTION_STATES:
		return
	p.set(&"anim_state", StringName(_current.name.to_lower()))
