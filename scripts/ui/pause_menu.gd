class_name PauseMenu
extends CanvasLayer
## Esc-triggered pause menu. Releases the cursor, blocks gameplay input, and —
## solo only — pauses the tree. Online play never pauses the tree (other peers
## keep running); the menu still opens and frees the cursor.

var _is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	visible = false
	_build_ui()
	Controls.pause_pressed.connect(_on_pause_pressed)


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -150.0
	panel.offset_right  =  150.0
	panel.offset_top    = -150.0
	panel.offset_bottom =  150.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	vbox.add_child(_make_button("Close", _on_close))
	vbox.add_child(_make_button("Save", _on_save))
	vbox.add_child(_make_button("Save & Quit", _on_save_quit))


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	return b


## Esc toggles the menu (PAUSE fires even while input is blocked).
func _on_pause_pressed() -> void:
	if _is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_is_open = true
	visible = true
	Controls.input_blocked = true
	Controls.release_mouse()
	# Solo only: freeze the world. Online, peers keep running.
	if NetworkManager.is_offline():
		get_tree().paused = true


func _close() -> void:
	_is_open = false
	visible = false
	Controls.input_blocked = false
	get_tree().paused = false
	Controls.capture_mouse()


func _on_close() -> void:
	_close()


func _on_save() -> void:
	_do_save()


func _on_save_quit() -> void:
	# Save while the world is still live (multiplayer peer + player nodes intact),
	# then tear down to a fresh lobby.
	_do_save()
	NetworkManager.return_to_lobby()


## Every peer saves its own profile; only the host writes the world save.
func _do_save() -> void:
	ProfileSave.save()
	if multiplayer.is_server():
		NetworkManager.record_all_player_positions()
		SaveSystem.save()
