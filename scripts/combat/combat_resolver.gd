class_name CombatResolver

## Phase 2: returns base_damage directly.
## Multipliers (skill, resistance) land with the full skill system.
static func resolve(
	_attacker: Node,
	_target: Node,
	_weapon_id: StringName,
	base_damage: float
) -> float:
	return base_damage
