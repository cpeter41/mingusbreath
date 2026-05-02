extends Node3D

const RAISED_POSITION  := Vector3(0.0, 0.25, -0.1)
const RAISED_ROTATION_X := -25.0  # degrees, tilts face toward attacker

var _raise_tween: Tween
var _lower_tween: Tween


func raise(duration: float) -> void:
	if _lower_tween:
		_lower_tween.kill()
	_raise_tween = create_tween().set_parallel(true)
	_raise_tween.tween_property(self, "position", RAISED_POSITION, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_raise_tween.tween_property(self, "rotation:x", deg_to_rad(RAISED_ROTATION_X), duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func lower() -> void:
	if _raise_tween:
		_raise_tween.kill()
	_lower_tween = create_tween().set_parallel(true)
	_lower_tween.tween_property(self, "position", Vector3.ZERO, 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_lower_tween.tween_property(self, "rotation:x", 0.0, 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
