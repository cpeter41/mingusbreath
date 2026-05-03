class_name StateMachine
extends Node

var _states: Dictionary = {}
var _current: BaseState = null


func transition_to(state_name: String) -> void:
	var next := _states.get(state_name) as BaseState
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


func current_state_name() -> String:
	return _current.name.to_lower() if _current else ""
