class_name FakeCombatant
extends Node
## Minimal stand-in for a Player or Enemy in combat tests — just enough surface
## for damage routing without instancing a full character scene. `Node` already
## provides `is_multiplayer_authority()`.

var hp: float = 100.0
var max_hp: float = 100.0
## Every take_damage() call, in order — lets a test assert on what was applied.
var damage_log: Array[Dictionary] = []


func take_damage(amount: float, attacker: Node = null) -> void:
	hp = maxf(0.0, hp - amount)
	damage_log.append({"amount": amount, "attacker": attacker})


func is_alive() -> bool:
	return hp > 0.0
