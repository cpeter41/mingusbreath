extends MovementState

const SWIM_SPEED      := 3.5
const SWIM_ACCEL      := 8.0
const BOB_FREQ        := 1.6
const BOB_AMPLITUDE   := 0.12
const SPRING_K        := 14.0
const DAMPING         := 5.0
const SURFACE_OFFSET  := -1.0
const SURFACE_EPSILON := 0.05
const WATER_JUMP_VELOCITY := 6.0

var _t: float = 0.0


func enter() -> void:
	_t = 0.0


func physics_update(delta: float) -> void:
	_t += delta

	if player.is_on_floor():
		var dir_in := _get_move_dir()
		movementSM.transition_to(
			"sprint" if Controls.sprint_held() and dir_in != Vector3.ZERO
			else "run" if dir_in != Vector3.ZERO
			else "idle"
		)
		return

	var target_y := OceanFollower.WATER_Y + sin(_t * BOB_FREQ) * BOB_AMPLITUDE + SURFACE_OFFSET

	if Controls.jump_just_pressed() and player.consume_stamina(15.0):
		movementSM.transition_to("jump")
		player.velocity.y = WATER_JUMP_VELOCITY
		return

	var dy := target_y - player.global_position.y
	player.velocity.y += (SPRING_K * dy - DAMPING * player.velocity.y) * delta

	var dir := _get_move_dir()
	if dir != Vector3.ZERO:
		var spd := SWIM_SPEED * (1.4 if Controls.sprint_held() else 1.0)
		player.velocity.x = move_toward(player.velocity.x, dir.x * spd, SWIM_ACCEL * delta)
		player.velocity.z = move_toward(player.velocity.z, dir.z * spd, SWIM_ACCEL * delta)
	else:
		_decelerate(delta)
