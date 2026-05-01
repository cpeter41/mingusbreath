class_name HUD
extends CanvasLayer

var _pickup_label: Label
var _pickup_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9

	var toast := SkillToast.new()
	add_child(toast)

	var inv_screen := InventoryScreen.new()
	add_child(inv_screen)

	_pickup_label = Label.new()
	_pickup_label.name = "PickupLabel"
	_pickup_label.anchor_left   = 0.0
	_pickup_label.anchor_right  = 0.0
	_pickup_label.anchor_top    = 1.0
	_pickup_label.anchor_bottom = 1.0
	_pickup_label.offset_left   =  20.0
	_pickup_label.offset_right  = 300.0
	_pickup_label.offset_top    = -60.0
	_pickup_label.offset_bottom = -20.0
	_pickup_label.add_theme_font_size_override("font_size", 18)
	_pickup_label.modulate.a = 0.0
	add_child(_pickup_label)

	EventBus.item_picked_up.connect(_on_item_picked_up)

func _on_item_picked_up(item_id: StringName, count: int) -> void:
	var def = InventoryRegistry.get_item(item_id)
	var name_str: String = def.display_name if def != null else str(item_id)
	_pickup_label.text = "+%d %s" % [count, name_str]

	if _pickup_tween:
		_pickup_tween.kill()
	_pickup_tween = create_tween()
	_pickup_tween.tween_property(_pickup_label, "modulate:a", 1.0, 0.15)
	_pickup_tween.tween_interval(1.5)
	_pickup_tween.tween_property(_pickup_label, "modulate:a", 0.0, 0.4)
