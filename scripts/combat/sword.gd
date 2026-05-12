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

var _rot_x_tween: Tween
var _rot_y_tween: Tween
var _hitframe_tween: Tween


## Called by Attack state. Re-entrant: kills any in-flight swing and starts a new one.
func swing() -> void:
	if _rot_x_tween:
		_rot_x_tween.kill()
	if _rot_y_tween:
		_rot_y_tween.kill()
	if _hitframe_tween:
		_hitframe_tween.kill()

	_rot_x_tween = create_tween()
	_rot_x_tween.tween_property(self, "rotation:x", deg_to_rad(20.0), WINDUP_DURATION)
	_rot_x_tween.tween_property(self, "rotation:x", deg_to_rad(-190.0), SWING_DURATION)
	_rot_x_tween.tween_property(self, "rotation:x", 0.0, RETURN_DURATION)

	_rot_y_tween = create_tween()
	_rot_y_tween.tween_property(self, "rotation:y", deg_to_rad(-20.0), WINDUP_DURATION)
	_rot_y_tween.tween_property(self, "rotation:y", deg_to_rad(45.0), SWING_DURATION)
	_rot_y_tween.tween_property(self, "rotation:y", 0.0, RETURN_DURATION)

	_hitframe_tween = create_tween()
	_hitframe_tween.tween_interval(WINDUP_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = true)
	_hitframe_tween.tween_interval(SWING_DURATION)
	_hitframe_tween.tween_callback(func(): hitbox.monitoring = false)

