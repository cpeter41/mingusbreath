class_name SkillToast
extends QueuedTextBanner


func _init() -> void:
	canvas_layer = 10
	hold_duration = 1.2


func _configure_label(label: Label) -> void:
	label.anchor_top    = 0.2
	label.anchor_bottom = 0.2
	label.offset_left   = -200.0
	label.offset_right  =  200.0
	label.offset_top    = -30.0
	label.offset_bottom =  30.0
	label.add_theme_font_size_override("font_size", 24)


func _after_ready() -> void:
	EventBus.skill_leveled.connect(_on_skill_leveled)


func _on_skill_leveled(skill_id: StringName, new_level: int) -> void:
	var def = SkillManager._defs.get(skill_id, null)
	var name_str: String = def.display_name if def != null else str(skill_id)
	enqueue("%s reached level %d" % [name_str, new_level])
