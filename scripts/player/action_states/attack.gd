extends ActionState

var _timer  := 0.0
var _sword: Sword


func enter() -> void:
	_sword = player.weapon_mount.get_node("Sword")
	_sword.swing()
	_timer = Sword.ATTACK_DURATION
	# Replicated: the setter fires the Attack clip on every peer. MovementSM
	# skips its own anim pushes while this action state is active so the swing
	# clip plays through uninterrupted.
	player.anim_state = &"attack"


func physics_update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		actionSM.transition_to("idle")
