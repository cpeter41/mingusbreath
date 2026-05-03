class_name StatBar
extends ProgressBar

var _tween: Tween


func _ready() -> void:
	min_value = 0.0
	max_value = 100.0
	value = 100.0
	step = 0.001
	show_percentage = false


func bind_to(stat_signal: Signal) -> void:
	stat_signal.connect(_on_stat_changed)


func _on_stat_changed(current: float, maximum: float) -> void:
	max_value = maximum
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "value", current, 0.1)
