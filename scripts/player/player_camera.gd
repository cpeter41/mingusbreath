extends SpringArm3D
## Third-person spring arm. Mouse input and pitch clamping live in player.gd.
## This script excludes the player's own physics body from spring arm raycasts.

func _ready() -> void:
	# Prevent spring arm from colliding with the player body it's attached to.
	add_excluded_object(owner.get_rid())
