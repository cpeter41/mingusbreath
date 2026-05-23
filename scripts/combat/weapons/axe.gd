extends Node3D

@onready var hitbox: Hitbox = $Hitbox

const ATTACK_DURATION := 1.0
const _WINDUP_RATIO := 0.25
const _SWING_RATIO := 0.5
const _RETURN_RATIO := 0.25

const WINDUP_DURATION := ATTACK_DURATION * _WINDUP_RATIO
const SWING_DURATION := ATTACK_DURATION * _SWING_RATIO
const RETURN_DURATION := ATTACK_DURATION * _RETURN_RATIO

var _hitframe_tween: Tween


func swing() -> void:
	if _hitframe_tween:
		_hitframe_tween.kill()
	_hitframe_tween = create_tween()
	_hitframe_tween.tween_interval(WINDUP_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = true)
	_hitframe_tween.tween_interval(SWING_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = false)
