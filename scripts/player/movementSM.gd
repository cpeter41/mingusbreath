extends Node

var player: CharacterBody3D
var _states: Dictionary = {}
var _current: MovementState = null


func _ready() -> void:
	player = owner as CharacterBody3D
	for child in get_children():
		if child is MovementState:
			_states[child.name.to_lower()] = child
			child.player = player
			child.movementSM = self
	# Defer so all _ready calls finish before first transition
	transition_to.call_deferred("fall")


func transition_to(state_name: String) -> void:
	var next := _states.get(state_name) as MovementState
	if next == null or next == _current:
		return
	if _current:
		_current.exit()
	_current = next
	_current.enter()


func physics_update(delta: float) -> void:
	if _current:
		_current.physics_update(delta)


func handle_input(event: InputEvent) -> void:
	if _current:
		_current.handle_input(event)
