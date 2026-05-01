extends Node

const SKILLS_DIR := "res://data/skills/"

var skills: Dictionary = {}
var _defs: Dictionary = {}  # StringName -> SkillDef

func _ready() -> void:
	_load_defs()
	SaveSystem.register(self)

func _load_defs() -> void:
	var d := DirAccess.open(SKILLS_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".tres"):
			var res := load(SKILLS_DIR + fname)
			if res != null and "id" in res:
				_defs[StringName(res.id)] = res
		fname = d.get_next()
	d.list_dir_end()

func add_xp(skill_id: StringName, amount: float) -> void:
	if not skills.has(skill_id):
		skills[skill_id] = {"level": 1, "xp": 0.0}
	var old_level: int = int(skills[skill_id].get("level", 1))
	skills[skill_id]["xp"] += amount
	EventBus.skill_xp_gained.emit(skill_id, amount)

	var new_level := _compute_level(skill_id)
	if new_level > old_level:
		# emit once per level gained so toast queue gets one signal per level
		for lvl in range(old_level + 1, new_level + 1):
			skills[skill_id]["level"] = lvl
			EventBus.skill_leveled.emit(skill_id, lvl)
			print("[SkillManager] skill_leveled %s -> %d" % [skill_id, lvl])

func _compute_level(skill_id: StringName) -> int:
	var xp: float = float(skills[skill_id].get("xp", 0.0))
	var def = _defs.get(skill_id, null)
	if def == null or def.xp_curve.size() == 0:
		return int(skills[skill_id].get("level", 1))
	var level := 1
	for threshold in def.xp_curve:
		if xp >= threshold:
			level += 1
		else:
			break
	return mini(level, def.xp_curve.size() + 1)

func get_level(skill_id: StringName) -> int:
	if skills.has(skill_id):
		return int(skills[skill_id].get("level", 1))
	return 1

func save_data() -> Dictionary:
	return {"skills": skills.duplicate(true)}

func load_data(d: Dictionary) -> void:
	skills = d.get("skills", {})
