class_name SkillToast
extends CanvasLayer

var _label: Label
var _queue: Array[String] = []
var _busy: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_left   = 0.5
	_label.anchor_right  = 0.5
	_label.anchor_top    = 0.2
	_label.anchor_bottom = 0.2
	_label.offset_left   = -200.0
	_label.offset_right  =  200.0
	_label.offset_top    = -30.0
	_label.offset_bottom =  30.0
	_label.add_theme_font_size_override("font_size", 24)
	_label.modulate.a = 0.0
	add_child(_label)

	EventBus.skill_leveled.connect(_on_skill_leveled)

func _on_skill_leveled(skill_id: StringName, new_level: int) -> void:
	var def = SkillManager._defs.get(skill_id, null)
	var name_str: String = def.display_name if def != null else str(skill_id)
	_queue.append("%s reached level %d" % [name_str, new_level])
	if not _busy:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	_label.text = _queue.pop_front()

	var t := create_tween()
	t.tween_property(_label, "modulate:a", 1.0, 0.3)
	t.tween_interval(1.2)
	t.tween_property(_label, "modulate:a", 0.0, 0.3)
	t.tween_callback(_show_next)
