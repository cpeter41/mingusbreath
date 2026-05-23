extends Node3D

# Dual-purpose: bulwark uses this for BOTH attack (bash) and block (raise/lower).

@onready var hitbox: Hitbox = $Hitbox

const ATTACK_DURATION := 0.7
const _WINDUP_RATIO := 0.2
const _SWING_RATIO := 0.6
const _RETURN_RATIO := 0.2

const WINDUP_DURATION := ATTACK_DURATION * _WINDUP_RATIO
const BASH_DURATION := ATTACK_DURATION * _SWING_RATIO
const RETURN_DURATION := ATTACK_DURATION * _RETURN_RATIO

const RAISED_POSITION  := Vector3(0.0, 0.25, -0.1)
const RAISED_ROTATION_X := -25.0

var _hitframe_tween: Tween
var _raise_tween: Tween
var _lower_tween: Tween


func bash() -> void:
	if _hitframe_tween:
		_hitframe_tween.kill()
	_hitframe_tween = create_tween()
	_hitframe_tween.tween_interval(WINDUP_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = true)
	_hitframe_tween.tween_interval(BASH_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = false)


func raise(duration: float) -> void:
	if _lower_tween:
		_lower_tween.kill()
	_raise_tween = create_tween().set_parallel(true)
	_raise_tween.tween_property(self, "position", RAISED_POSITION, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_raise_tween.tween_property(self, "rotation:x", deg_to_rad(RAISED_ROTATION_X), duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func lower() -> void:
	if _raise_tween:
		_raise_tween.kill()
	_lower_tween = create_tween().set_parallel(true)
	_lower_tween.tween_property(self, "position", Vector3.ZERO, 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_lower_tween.tween_property(self, "rotation:x", 0.0, 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
