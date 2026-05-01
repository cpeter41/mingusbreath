extends Node3D

@onready var hitbox: Hitbox = $Hitbox

var attack_duration := 0.8

# all ratios must add to 1
const _WINDUP_RATIO := 0.1875	# 0.8s * 0.1875 = 0.15s
const _SWING_RATIO := 0.625
const _RETURN_RATIO := 0.1875

var windup_duration := attack_duration * _WINDUP_RATIO
var swing_duration := attack_duration * _SWING_RATIO
var return_duration := attack_duration * _RETURN_RATIO

## Called by Attack state.
func swing() -> void:
#	swing animation with active hitframes
	var rot_x := create_tween()
	rot_x.tween_property(self, "rotation:x", deg_to_rad(20.0), windup_duration)
	rot_x.tween_property(self, "rotation:x", deg_to_rad(-190.0), swing_duration)
	rot_x.tween_property(self, "rotation:x", 0.0, return_duration)
	
	var rot_y := create_tween()
	rot_y.tween_property(self, "rotation:y", deg_to_rad(-20.0), windup_duration)
	rot_y.tween_property(self, "rotation:y", deg_to_rad(45.0), swing_duration)
	rot_y.tween_property(self, "rotation:y", 0.0, return_duration)
	
	var t := create_tween()
	t.tween_interval(windup_duration)
	t.tween_callback(func(): hitbox.monitoring = true)
	t.tween_interval(swing_duration)
	t.tween_callback(func(): hitbox.monitoring = false)
	
