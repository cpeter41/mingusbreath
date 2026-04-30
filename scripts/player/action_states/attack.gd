extends ActionState

const DURATION := 0.6

var _timer  := 0.0
var _sword: Node3D


func enter() -> void:
	_sword = player.get_node("WeaponMount/Sword")
	_sword.swing()
	_timer = DURATION


func physics_update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		actionSM.transition_to("idle")
