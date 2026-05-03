extends ActionState

const DODGE_SPEED    := 13.0
const DODGE_DURATION := 0.25

var _timer: float     = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO


func enter() -> void:
	_timer = DODGE_DURATION
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input != Vector2.ZERO:
		_dodge_dir = (player.transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	else:
		_dodge_dir = (player.transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	if player.hurtbox:
		player.hurtbox.monitorable = false


func physics_update(delta: float) -> void:
	_timer -= delta
	var t := clampf(1.0 - _timer / DODGE_DURATION, 0.0, 1.0)
	var speed := lerpf(DODGE_SPEED, player.speed, smoothstep(0.0, 1.0, t))
	player.velocity.x = _dodge_dir.x * speed
	player.velocity.z = _dodge_dir.z * speed
	if _timer <= 0.0:
		actionSM.transition_to("idle")


func exit() -> void:
	if player.hurtbox:
		player.hurtbox.monitorable = true
