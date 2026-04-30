extends MovementState

const SPEED         := 5.0
const JUMP_VELOCITY := 4.5

func enter() -> void:
	player.velocity.y = JUMP_VELOCITY
	SkillManager.add_xp(&"jump", 1.0)

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var dir := _get_move_dir()
	if dir != Vector3.ZERO:
		player.velocity.x = dir.x * SPEED
		player.velocity.z = dir.z * SPEED

	if player.velocity.y <= 0.0:
		movementSM.transition_to("fall")
