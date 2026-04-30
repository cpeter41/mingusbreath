extends Node3D

@onready var hitbox: Hitbox = $Hitbox

## Called by Attack state. Tween swings blade; hitbox active 0.05–0.25 s.
func swing() -> void:
	var t := create_tween()
	t.tween_interval(0.05)
	t.tween_callback(func(): hitbox.monitoring = true)
	t.tween_interval(0.20)
	t.tween_callback(func(): hitbox.monitoring = false)

	var rot := create_tween()
	rot.tween_property(self, "rotation:x", deg_to_rad(-110.0), 0.20)
	rot.tween_property(self, "rotation:x", 0.0, 0.15)
