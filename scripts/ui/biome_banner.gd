class_name BiomeBanner
extends CanvasLayer

var _label: Label
var _queue: Array[String] = []
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 8

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_left   = 0.5
	_label.anchor_right  = 0.5
	_label.anchor_top    = 0.35
	_label.anchor_bottom = 0.35
	_label.offset_left   = -250.0
	_label.offset_right  =  250.0
	_label.offset_top    = -40.0
	_label.offset_bottom =  40.0
	_label.add_theme_font_size_override("font_size", 32)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_label.modulate.a = 0.0
	add_child(_label)

	EventBus.biome_entered.connect(_on_biome_entered)


func _on_biome_entered(biome: BiomeDef) -> void:
	if biome == null:
		return
	_queue.append(biome.display_name)
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
	t.tween_interval(1.4)
	t.tween_property(_label, "modulate:a", 0.0, 0.3)
	t.tween_callback(_show_next)
