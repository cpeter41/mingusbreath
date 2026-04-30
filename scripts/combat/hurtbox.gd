class_name Hurtbox
extends Area3D

## Passive receiver — hitboxes detect this, not the other way around.
func _ready() -> void:
	collision_layer = 4   # "hurtbox" layer — hitboxes scan for this
	monitoring  = false   # hurtbox never needs to scan for anything
	monitorable = true    # hitboxes can see this
