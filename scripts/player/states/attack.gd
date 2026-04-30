extends PlayerState

const DURATION := 0.6

var _timer  := 0.0
var _sword: Node3D


func enter() -> void:
	_sword = player.get_node("WeaponMount/Sword")
	_sword.swing()
	_timer = DURATION


func physics_update(delta: float) -> void:
	_apply_gravity(delta)

	# Slide to a stop during the swing
	player.velocity.x = move_toward(player.velocity.x, 0.0, 10.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, 10.0 * delta)

	_timer -= delta
	if _timer <= 0.0:
		state_machine.transition_to("idle")
