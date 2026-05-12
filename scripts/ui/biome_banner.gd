class_name BiomeBanner
extends QueuedTextBanner


func _init() -> void:
	canvas_layer = 8
	hold_duration = 1.4


func _configure_label(label: Label) -> void:
	label.anchor_top    = 0.35
	label.anchor_bottom = 0.35
	label.offset_left   = -250.0
	label.offset_right  =  250.0
	label.offset_top    = -40.0
	label.offset_bottom =  40.0
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


func _after_ready() -> void:
	EventBus.biome_entered.connect(_on_biome_entered)


func _on_biome_entered(biome: BiomeDef) -> void:
	if biome == null:
		return
	enqueue(biome.display_name)
