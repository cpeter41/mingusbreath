extends MovementState

const SPEED         := 5.0
const JUMP_VELOCITY := 4.5
const AIR_ACCEL     := 10.0	# consider moving this to a global

func enter() -> void:
	player.velocity.y = JUMP_VELOCITY
	SkillManager.add_xp(&"jump", 1.0)

func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	var dir := _get_move_dir()
	if dir != Vector3.ZERO:
		player.velocity.x = move_toward(player.velocity.x, dir.x * SPEED, AIR_ACCEL * delta)
		player.velocity.z = move_toward(player.velocity.z, dir.z * SPEED, AIR_ACCEL * delta)

	if player.velocity.y <= 0.0:
		movementSM.transition_to("fall")
