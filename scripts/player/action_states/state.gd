class_name ActionState
extends Node

var player: CharacterBody3D
var actionSM: Node  # PlayerStateMachine, typed as Node to avoid circular ref

func enter() -> void: pass
func exit() -> void: pass
func physics_update(_delta: float) -> void: pass
func handle_input(_event: InputEvent) -> void: pass
