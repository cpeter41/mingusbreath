class_name HUD
extends CanvasLayer

var _pickup_label: Label
var _pickup_tween: Tween
var _death_fade: ColorRect
var _death_tween: Tween
var _coords_label: Label
var _biome_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9

	var toast := SkillToast.new()
	add_child(toast)

	var banner := BiomeBanner.new()
	add_child(banner)

	var inv_screen := InventoryScreen.new()
	add_child(inv_screen)

	var map_screen := MapScreen.new()
	add_child(map_screen)

	_add_stat_bars()
	_add_pickup_label()
	_add_death_fade()
	_add_coords_label()
	_add_biome_label()

	var legend := ControlsLegend.new()
	legend.name = "ControlsLegend"
	add_child(legend)

	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.biome_entered.connect(_on_biome_entered)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_respawned.connect(_on_player_respawned)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var p := player.global_position
	_coords_label.text = "%.1f  %.1f  %.1f" % [p.x, p.y, p.z]


func _add_stat_bars() -> void:
	var hp_bar := StatBar.new()
	hp_bar.name = "HPBar"
	hp_bar.anchor_left   = 0.0
	hp_bar.anchor_right  = 0.0
	hp_bar.anchor_top    = 0.0
	hp_bar.anchor_bottom = 0.0
	hp_bar.offset_left   = 16.0
	hp_bar.offset_right  = 216.0
	hp_bar.offset_top    = 16.0
	hp_bar.offset_bottom = 46.0
	hp_bar.add_theme_color_override("font_color", Color.WHITE)
	_apply_bar_styles(hp_bar, Color(0.8, 0.15, 0.15))
	add_child(hp_bar)
	hp_bar.bind_to(EventBus.player_hp_changed)

	var stamina_bar := StatBar.new()
	stamina_bar.name = "StaminaBar"
	stamina_bar.anchor_left   = 0.0
	stamina_bar.anchor_right  = 0.0
	stamina_bar.anchor_top    = 0.0
	stamina_bar.anchor_bottom = 0.0
	stamina_bar.offset_left   = 16.0
	stamina_bar.offset_right  = 216.0
	stamina_bar.offset_top    = 54.0
	stamina_bar.offset_bottom = 84.0
	_apply_bar_styles(stamina_bar, Color(0.15, 0.75, 0.25))
	add_child(stamina_bar)
	stamina_bar.bind_to(EventBus.player_stamina_changed)


func _apply_bar_styles(bar: ProgressBar, fill_color: Color, radius: int = 5) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.12)
	bg.corner_radius_top_left     = radius
	bg.corner_radius_top_right    = radius
	bg.corner_radius_bottom_left  = radius
	bg.corner_radius_bottom_right = radius
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left     = radius
	fill.corner_radius_top_right    = radius
	fill.corner_radius_bottom_left  = radius
	fill.corner_radius_bottom_right = radius
	bar.add_theme_stylebox_override("fill", fill)


func _add_coords_label() -> void:
	_coords_label = Label.new()
	_coords_label.name = "CoordsLabel"
	_coords_label.anchor_left   = 0.0
	_coords_label.anchor_right  = 0.0
	_coords_label.anchor_top    = 0.0
	_coords_label.anchor_bottom = 0.0
	_coords_label.offset_left   = 16.0
	_coords_label.offset_right  = 280.0
	_coords_label.offset_top    = 92.0
	_coords_label.offset_bottom = 114.0
	_coords_label.add_theme_font_size_override("font_size", 14)
	_coords_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	add_child(_coords_label)


func _add_biome_label() -> void:
	_biome_label = Label.new()
	_biome_label.name = "BiomeLabel"
	_biome_label.anchor_left   = 0.0
	_biome_label.anchor_right  = 0.0
	_biome_label.anchor_top    = 0.0
	_biome_label.anchor_bottom = 0.0
	_biome_label.offset_left   = 148.0
	_biome_label.offset_right  = 500.0
	_biome_label.offset_top    = 92.0
	_biome_label.offset_bottom = 114.0
	_biome_label.add_theme_font_size_override("font_size", 14)
	_biome_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	add_child(_biome_label)


func _add_pickup_label() -> void:
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


func _add_death_fade() -> void:
	_death_fade = ColorRect.new()
	_death_fade.name = "DeathFade"
	_death_fade.color = Color.BLACK
	_death_fade.modulate.a = 0.0
	_death_fade.anchor_left   = 0.0
	_death_fade.anchor_right  = 1.0
	_death_fade.anchor_top    = 0.0
	_death_fade.anchor_bottom = 1.0
	_death_fade.offset_left   = 0.0
	_death_fade.offset_right  = 0.0
	_death_fade.offset_top    = 0.0
	_death_fade.offset_bottom = 0.0
	_death_fade.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_death_fade)


func _on_player_died() -> void:
	if _death_tween:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(_death_fade, "modulate:a", 1.0, 0.6)


func _on_player_respawned() -> void:
	if _death_tween:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(_death_fade, "modulate:a", 0.0, 0.6)


func _on_biome_entered(biome: BiomeDef) -> void:
	_biome_label.text = biome.display_name


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
