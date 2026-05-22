class_name Sword
extends Node3D

@onready var hitbox: Hitbox = $Hitbox

const ATTACK_DURATION := 0.8

# all ratios must add to 1
const _WINDUP_RATIO := 0.1875	# 0.8s * 0.1875 = 0.15s
const _SWING_RATIO := 0.625
const _RETURN_RATIO := 0.1875

const WINDUP_DURATION := ATTACK_DURATION * _WINDUP_RATIO
const SWING_DURATION := ATTACK_DURATION * _SWING_RATIO
const RETURN_DURATION := ATTACK_DURATION * _RETURN_RATIO

var _hitframe_tween: Tween


## Called by Attack state. Re-entrant: kills any in-flight swing and starts a new one.
func swing() -> void:
	if _hitframe_tween:
		_hitframe_tween.kill()

	# Swing rotation animation removed — the rig swept rotation:x to -190deg
	# through the player body. Hitframe timing kept so the attack still deals damage.
	_hitframe_tween = create_tween()
	_hitframe_tween.tween_interval(WINDUP_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = true)
	_hitframe_tween.tween_interval(SWING_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = false)

