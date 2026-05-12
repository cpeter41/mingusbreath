## Base for a CanvasLayer that fades a queue of strings through a single Label.
## Subclasses override _configure_label() to set anchors, font size, etc.
class_name QueuedTextBanner
extends CanvasLayer

@export var hold_duration: float = 1.4
@export var fade_duration: float = 0.3
@export var canvas_layer: int = 8

var _label: Label
var _queue: Array[String] = []
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = canvas_layer
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.modulate.a = 0.0
	_configure_label(_label)
	add_child(_label)
	_after_ready()


## Override to set anchor_top/bottom, offsets, font size/color.
func _configure_label(_label_node: Label) -> void:
	pass


## Override to subscribe to events that drive enqueue().
func _after_ready() -> void:
	pass


func enqueue(text: String) -> void:
	_queue.append(text)
	if not _busy:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	_label.text = _queue.pop_front()

	var t := create_tween()
	t.tween_property(_label, "modulate:a", 1.0, fade_duration)
	t.tween_interval(hold_duration)
	t.tween_property(_label, "modulate:a", 0.0, fade_duration)
	t.tween_callback(_show_next)
