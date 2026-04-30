extends Node

var skills: Dictionary = {}

func _ready() -> void:
	SaveSystem.register(self)   #saves xp between runs

func add_xp(skill_id: StringName, amount: float) -> void:
	if not skills.has(skill_id):
		skills[skill_id] = {"level": 1, "xp": 0.0}
	skills[skill_id]["xp"] += amount
	EventBus.skill_xp_gained.emit(skill_id, amount)

func get_level(skill_id: StringName) -> int:
	if skills.has(skill_id):
		return int(skills[skill_id].get("level", 1))
	return 1

func save_data() -> Dictionary:
	return {"skills": skills.duplicate(true)}

func load_data(d: Dictionary) -> void:
	skills = d.get("skills", {})
