extends Node

var skills: Dictionary = {}

func add_xp(_skill_id: StringName, _amount: float) -> void:
	pass

func get_level(skill_id: StringName) -> int:
	if skills.has(skill_id):
		return int(skills[skill_id].get("level", 1))
	return 1
