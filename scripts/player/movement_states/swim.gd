extends MovementState

const SWIM_SPEED      := 3.5
const SWIM_ACCEL      := 8.0
const SPRING_K        := 20.0
const DAMPING         := 9.0
const SURFACE_OFFSET  := -1.0
const SURFACE_EPSILON := 0.05
const WATER_JUMP_VELOCITY := 6.0


func enter() -> void:
	pass


func physics_update(delta: float) -> void:
	if player.is_on_floor():
		var dir_in := _get_move_dir()
		movementSM.transition_to(
			"sprint" if Controls.sprint_held() and dir_in != Vector3.ZERO
			else "run" if dir_in != Vector3.ZERO
			else "idle"
		)
		return

	var p := player.global_position
	var target_y := Ocean.get_height(p.x, p.z, Ocean.time) + SURFACE_OFFSET

	if Controls.jump_just_pressed() and player.consume_stamina(15.0):
		movementSM.transition_to("jump")
		player.velocity.y = WATER_JUMP_VELOCITY
		return

	var dy := target_y - p.y
	player.velocity.y += (SPRING_K * dy - DAMPING * player.velocity.y) * delta

	var dir := _get_move_dir()
	if dir != Vector3.ZERO:
		var spd := SWIM_SPEED * (1.4 if Controls.sprint_held() else 1.0)
		player.velocity.x = move_toward(player.velocity.x, dir.x * spd, SWIM_ACCEL * delta)
		player.velocity.z = move_toward(player.velocity.z, dir.z * spd, SWIM_ACCEL * delta)
	else:
		_decelerate(delta)
