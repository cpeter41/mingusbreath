extends ActionState

const PARRY_WINDOW := 0.15

var _parry_timer: float = 0.0


func enter() -> void:
	player.is_blocking = true
	player.is_parrying = true
	_parry_timer = PARRY_WINDOW
	var shield := _get_shield()
	if shield:
		shield.raise(PARRY_WINDOW)


func physics_update(delta: float) -> void:
	if _parry_timer > 0.0:
		_parry_timer -= delta
		if _parry_timer <= 0.0:
			player.is_parrying = false

	if not Controls.block_held() or not player.has_block_weapon():
		actionSM.transition_to("idle")


func exit() -> void:
	player.is_blocking = false
	player.is_parrying = false
	var shield := _get_shield()
	if shield:
		shield.lower()


func _get_shield() -> Node3D:
	if player.weapon_mount == null or player.weapon_mount.get_child_count() == 0:
		return null
	return player.weapon_mount.get_child(0) as Node3D
