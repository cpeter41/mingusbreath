extends ActionState

const ATTACK_DURATION := 0.8
const FIRE_DELAY := 0.25

var _timer := 0.0
var _fire_timer := 0.0
var _fired := false
var _weapon: Node


func enter() -> void:
	_weapon = player.weapon_mount.get_child(0) if player.weapon_mount.get_child_count() > 0 else null
	_timer = ATTACK_DURATION
	_fire_timer = FIRE_DELAY
	_fired = false
	player.anim_state = &"attack"


func physics_update(delta: float) -> void:
	_timer -= delta
	if not _fired:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fired = true
			if _weapon != null and _weapon.has_method("fire") and player.is_multiplayer_authority():
				_weapon.fire(player)
	if _timer <= 0.0:
		actionSM.transition_to("idle")
