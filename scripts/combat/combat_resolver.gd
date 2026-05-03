class_name CombatResolver

static func resolve(
	_attacker: Node,
	_target: Node,
	_weapon_id: StringName,
	base_damage: float,
	skill_id: StringName = &""
) -> float:
	var level := SkillManager.get_level(skill_id) if skill_id != &"" else 1
	return base_damage * (1.0 + 0.1 * (level - 1))
