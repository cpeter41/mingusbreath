extends EnemyMovementState

var _target: Vector3 = Vector3.ZERO
var _has_target: bool = false
const WANDER_RADIUS := 10.0
const ARRIVE_THRESHOLD := 1.0

func enter() -> void:
	_pick_target()


func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	# Sense check — detect player each tick
	var player := enemy.get_player()
	if player:
		var dist := enemy.global_position.distance_to(player.global_position)
		if dist <= enemy.def.sense_radius:
			movementSM.transition_to("sense")
			return

	if not _has_target:
		_pick_target()

	var dir := (_target - enemy.global_position)
	dir.y = 0.0
	if dir.length() < ARRIVE_THRESHOLD:
		_has_target = false
		movementSM.transition_to("idle")
		return

	dir = dir.normalized()
	enemy.velocity.x = dir.x * enemy.def.move_speed * 0.5
	enemy.velocity.z = dir.z * enemy.def.move_speed * 0.5


func _pick_target() -> void:
	var offset := Vector3(
		randf_range(-WANDER_RADIUS, WANDER_RADIUS),
		0.0,
		randf_range(-WANDER_RADIUS, WANDER_RADIUS)
	)
	_target = enemy.spawn_anchor + offset
	_target.y = enemy.global_position.y
	_has_target = true
