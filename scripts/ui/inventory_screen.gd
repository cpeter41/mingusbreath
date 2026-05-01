class_name InventoryScreen
extends CanvasLayer

const COLS := 5
const SLOT_SIZE := Vector2(100, 72)

var _grid: GridContainer
var _tooltip: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false
	_build_ui()

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -270.0
	panel.offset_right  =  270.0
	panel.offset_top    = -230.0
	panel.offset_bottom =  230.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Inventory"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_grid)

	# Tooltip label — floats above grid, hidden until hover
	_tooltip = Label.new()
	_tooltip.visible = false
	_tooltip.z_index = 10
	_tooltip.add_theme_font_size_override("font_size", 14)
	_tooltip.add_theme_color_override("font_color", Color.WHITE)
	var tp_bg := StyleBoxFlat.new()
	tp_bg.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	tp_bg.set_corner_radius_all(4)
	tp_bg.content_margin_left   = 6
	tp_bg.content_margin_right  = 6
	tp_bg.content_margin_top    = 4
	tp_bg.content_margin_bottom = 4
	_tooltip.add_theme_stylebox_override("normal", tp_bg)
	add_child(_tooltip)

func _rebuild_slots() -> void:
	for child in _grid.get_children():
		child.queue_free()

	var player := get_tree().get_first_node_in_group("player")
	var slots: Array = player.inventory.slots if player else []

	var total := InventoryScreen._ceil_to_grid(maxi(slots.size(), 1), COLS)
	for i in range(total):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = SLOT_SIZE

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

		if i < slots.size():
			var entry: Dictionary = slots[i]
			var def = InventoryRegistry.get_item(entry["item_id"])
			var name_str: String = def.display_name if def != null else str(entry["item_id"])
			label.text = "%s\nx%d" % [name_str, entry["count"]]
			var desc: String = def.description if def != null else ""
			if desc != "":
				slot_panel.mouse_entered.connect(_show_tooltip.bind(desc, slot_panel))
				slot_panel.mouse_exited.connect(_hide_tooltip)

		slot_panel.add_child(label)
		_grid.add_child(slot_panel)

func _show_tooltip(desc: String, anchor: Control) -> void:
	_tooltip.text = desc
	_tooltip.visible = true
	# Position just above the slot
	var pos := anchor.get_global_rect().position
	_tooltip.position = pos + Vector2(0, -50)

func _hide_tooltip() -> void:
	_tooltip.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle()

func _toggle() -> void:
	visible = !visible
	get_tree().paused = visible
	if visible:
		_rebuild_slots()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

static func _ceil_to_grid(n: int, cols: int) -> int:
	return int(ceil(float(n) / cols)) * cols
