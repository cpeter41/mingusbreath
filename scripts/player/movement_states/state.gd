class_name MovementState
extends BaseState

const DECELERATION_MOD := 10.0

var player: CharacterBody3D
var movementSM: StateMachine  # concrete type causes circular ref


func _apply_gravity(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y -= player.gravity * delta

func _get_move_dir() -> Vector3:
	var input := Controls.move_vector()
	return (player.transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

func _decelerate(delta: float) -> void:
	player.velocity.x = move_toward(player.velocity.x, 0.0, DECELERATION_MOD * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, DECELERATION_MOD * delta)
