class_name ChatPanel
extends Control
# Bottom-left chat overlay. Enter opens input, Enter sends, Esc cancels.
# Messages broadcast to all peers via NetworkManager.broadcast_chat / EventBus.
# "/" prefix messages are emitted locally as chat_command_entered, not broadcast.

const MAX_MESSAGES   := 20
const FADE_DELAY     := 6.0   # seconds idle before history fades
const FADE_DURATION  := 2.0   # seconds for the fade-out tween
const NAME_COLOR     := "#88ccff"

var _is_open: bool = false
var _history: RichTextLabel
var _input_line: LineEdit
var _background: PanelContainer
var _fade_tween: Tween
var _messages: Array[Dictionary] = []   # {sender: String, text: String}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Controls.chat_open_pressed.connect(_on_chat_open_pressed)
	EventBus.chat_message_received.connect(_on_message_received)


func _build_ui() -> void:
	# Anchor everything to the bottom-left corner.
	anchor_left   = 0.0
	anchor_right  = 0.0
	anchor_top    = 1.0
	anchor_bottom = 1.0
	offset_left   = 0.0
	offset_right  = 0.0
	offset_top    = 0.0
	offset_bottom = 0.0
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	# Semi-transparent background — only shown while input is open.
	_background = PanelContainer.new()
	_background.name = "Background"
	_background.anchor_left   = 0.0
	_background.anchor_right  = 0.0
	_background.anchor_top    = 1.0
	_background.anchor_bottom = 1.0
	_background.offset_left   = 12.0
	_background.offset_right  = 424.0
	_background.offset_top    = -264.0
	_background.offset_bottom = -80.0
	_background.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.05, 0.55)
	bg_style.corner_radius_top_left     = 4
	bg_style.corner_radius_top_right    = 4
	bg_style.corner_radius_bottom_left  = 4
	bg_style.corner_radius_bottom_right = 4
	_background.add_theme_stylebox_override("panel", bg_style)
	_background.visible = false
	add_child(_background)

	# Message history — scrolling RichTextLabel.
	_history = RichTextLabel.new()
	_history.name = "History"
	_history.anchor_left   = 0.0
	_history.anchor_right  = 0.0
	_history.anchor_top    = 1.0
	_history.anchor_bottom = 1.0
	_history.offset_left   = 16.0
	_history.offset_right  = 420.0
	_history.offset_top    = -260.0
	_history.offset_bottom = -82.0
	_history.bbcode_enabled = true
	_history.scroll_following = true
	_history.scroll_active = false
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_history.add_theme_font_size_override("normal_font_size", 14)
	_history.modulate.a = 0.0
	add_child(_history)

	# Text input — hidden until Enter is pressed.
	_input_line = LineEdit.new()
	_input_line.name = "InputLine"
	_input_line.anchor_left   = 0.0
	_input_line.anchor_right  = 0.0
	_input_line.anchor_top    = 1.0
	_input_line.anchor_bottom = 1.0
	_input_line.offset_left   = 16.0
	_input_line.offset_right  = 420.0
	_input_line.offset_top    = -78.0
	_input_line.offset_bottom = -56.0
	_input_line.placeholder_text = "Press Enter to send, Esc to cancel…"
	_input_line.max_length = 200
	_input_line.visible = false
	_input_line.text_submitted.connect(_on_text_submitted)
	# Style the input field to match the dark theme.
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.08, 0.08, 0.08, 0.80)
	input_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	input_style.set_border_width_all(1)
	input_style.corner_radius_top_left     = 3
	input_style.corner_radius_top_right    = 3
	input_style.corner_radius_bottom_left  = 3
	input_style.corner_radius_bottom_right = 3
	input_style.content_margin_left  = 6.0
	input_style.content_margin_right = 6.0
	_input_line.add_theme_stylebox_override("normal", input_style)
	_input_line.add_theme_stylebox_override("focus", input_style)
	add_child(_input_line)


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Intercept Esc before Controls._unhandled_input emits pause_pressed.
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _on_chat_open_pressed() -> void:
	# Don't open if the game tree is paused (inventory/map open) or already open.
	if get_tree().paused or _is_open:
		return
	_open()


# ── Open / close ──────────────────────────────────────────────────────────────

func _open() -> void:
	_is_open = true
	Controls.input_blocked = true
	Controls.allow_movement_while_blocked = false
	Controls.release_mouse()
	_cancel_fade()
	_history.modulate.a = 1.0
	_background.visible = true
	_input_line.visible = true
	_input_line.text = ""
	_input_line.grab_focus()


func _close() -> void:
	_is_open = false
	Controls.input_blocked = false
	Controls.capture_mouse()
	_input_line.visible = false
	_input_line.text = ""
	_background.visible = false
	_start_fade_timer()


# ── Message handling ──────────────────────────────────────────────────────────

func _on_text_submitted(raw: String) -> void:
	_close()
	var msg := raw.strip_edges()
	if msg.is_empty():
		return
	if msg.begins_with("/"):
		# Commands are local-only; wired up by a future handler.
		EventBus.chat_command_entered.emit(msg)
		return
	var sender := ProfileSave.current_character
	if sender.is_empty():
		sender = "Player_%d" % multiplayer.get_unique_id()
	NetworkManager.broadcast_chat(sender, msg)


func _on_message_received(sender: String, text: String) -> void:
	_messages.append({"sender": sender, "text": text})
	if _messages.size() > MAX_MESSAGES:
		_messages.pop_front()
	_rebuild_history()
	_cancel_fade()
	_history.modulate.a = 1.0
	if not _is_open:
		_start_fade_timer()


func _rebuild_history() -> void:
	_history.clear()
	for entry in _messages:
		var line := "[color=%s]%s:[/color] %s\n" % [
			NAME_COLOR,
			entry["sender"].xml_escape(),
			entry["text"].xml_escape(),
		]
		_history.append_text(line)


# ── Fade tween ────────────────────────────────────────────────────────────────

func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _start_fade_timer() -> void:
	_cancel_fade()
	if _messages.is_empty():
		return
	_fade_tween = create_tween()
	_fade_tween.tween_interval(FADE_DELAY)
	_fade_tween.tween_property(_history, "modulate:a", 0.0, FADE_DURATION)
