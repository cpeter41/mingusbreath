## Bottom-of-HUD readout of every bound input action.
## Rebuilds when InputMap changes (poll every REFRESH_S) so adding/removing
## actions in project.godot is reflected without manual edits here.
class_name ControlsLegend
extends Control

const REFRESH_S := 0.5

# Actions intentionally hidden from the legend. Keep one entry per line
# so the reason for each omission stays obvious.
const HIDDEN_ACTIONS := {
	&"fire_cannon": true,     # Shares LMB with attack_light; one entry is enough.
	&"move_forward": true,    # WASD movement is universal — collapse to avoid clutter.
	&"move_back": true,       # WASD movement is universal — collapse to avoid clutter.
	&"move_left": true,       # WASD movement is universal — collapse to avoid clutter.
	&"move_right": true,      # WASD movement is universal — collapse to avoid clutter.
	&"rudder_left": true,     # Duplicate of move_left while piloting a boat.
	&"rudder_right": true,    # Duplicate of move_right while piloting a boat.
	&"throttle_up": true,     # Duplicate of move_forward while piloting a boat.
	&"throttle_down": true,   # Duplicate of move_back while piloting a boat.
}

var _flow: HFlowContainer
var _signature: String = ""
var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 12.0
	offset_right = -12.0
	offset_top = -52.0
	offset_bottom = -8.0

	_flow = HFlowContainer.new()
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.add_theme_constant_override("h_separation", 18)
	_flow.add_theme_constant_override("v_separation", 2)
	_flow.anchor_left = 0.0
	_flow.anchor_right = 1.0
	_flow.anchor_top = 0.0
	_flow.anchor_bottom = 1.0
	add_child(_flow)

	_rebuild()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_S:
		return
	_timer = 0.0
	var sig := _compute_signature()
	if sig != _signature:
		_rebuild()


func _compute_signature() -> String:
	var parts: Array = []
	for action in InputMap.get_actions():
		var s := String(action)
		if s.begins_with("ui_"):
			continue
		if HIDDEN_ACTIONS.has(StringName(s)):
			continue
		var ev_parts: Array = []
		for ev in InputMap.action_get_events(action):
			ev_parts.append(_event_label(ev))
		parts.append(s + "=" + ",".join(ev_parts))
	parts.sort()
	return "|".join(parts)


func _rebuild() -> void:
	_signature = _compute_signature()
	for c in _flow.get_children():
		c.queue_free()

	var actions: Array = []
	for a in InputMap.get_actions():
		var s := String(a)
		if s.begins_with("ui_"):
			continue
		if HIDDEN_ACTIONS.has(StringName(s)):
			continue
		actions.append(s)
	actions.sort()

	for action in actions:
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			continue
		var key_strs: Array = []
		for ev in events:
			var lbl := _event_label(ev)
			if lbl != "":
				key_strs.append(lbl)
		if key_strs.is_empty():
			continue
		var entry := Label.new()
		entry.text = "[%s] %s" % ["/".join(key_strs), _humanize(action)]
		entry.add_theme_font_size_override("font_size", 12)
		entry.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		entry.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		entry.add_theme_constant_override("outline_size", 4)
		_flow.add_child(entry)


func _humanize(action: String) -> String:
	var words := action.replace("_", " ").split(" ")
	var out: Array = []
	for w in words:
		if w.length() == 0:
			continue
		out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)


func _event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		if code == 0:
			return ""
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		var m := ev as InputEventMouseButton
		match m.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel↑"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel↓"
			_: return "Mouse%d" % m.button_index
	if ev is InputEventJoypadButton:
		return "Pad%d" % (ev as InputEventJoypadButton).button_index
	return ""
