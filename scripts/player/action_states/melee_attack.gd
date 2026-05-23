extends ActionState

const ATTACK_DURATION := 0.8

var _timer := 0.0
var _weapon: Node


func enter() -> void:
	_weapon = player.weapon_mount.get_child(0) if player.weapon_mount.get_child_count() > 0 else null
	if _weapon != null and _weapon.has_method("swing"):
		_weapon.swing()
	_timer = ATTACK_DURATION
	player.anim_state = &"attack"


func physics_update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		actionSM.transition_to("idle")
