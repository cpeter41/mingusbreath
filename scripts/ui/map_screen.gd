class_name MapScreen
extends CanvasLayer

const SCREEN_MARGIN := 80.0

var _canvas: MapCanvas
var _coords: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false
	_build_ui()
	Controls.map_toggled.connect(_toggle)

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left   =  SCREEN_MARGIN
	panel.offset_right  = -SCREEN_MARGIN
	panel.offset_top    =  SCREEN_MARGIN
	panel.offset_bottom = -SCREEN_MARGIN
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Map"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(aspect)

	_canvas = MapCanvas.new()
	aspect.add_child(_canvas)

	_coords = Label.new()
	_coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coords.add_theme_font_size_override("font_size", 14)
	_coords.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	vbox.add_child(_coords)

func _process(_delta: float) -> void:
	if not visible:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		_coords.text = ""
		return
	var p := player.global_position
	_coords.text = "X %.1f   Z %.1f" % [p.x, p.z]

func _toggle() -> void:
	visible = !visible
	get_tree().paused = visible
	if visible:
		Controls.release_mouse()
		_canvas.queue_redraw()
	else:
		Controls.capture_mouse()


class MapCanvas extends Control:
	const WORLD_SIZE := 8192.0  # IslandRegistry.WORLD_SIZE_M

	func _process(_delta: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var s := size
		# Ocean.
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.10, 0.20, 0.35), true)
		# Border.
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.9, 0.9, 0.6), false, 2.0)

		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()

		# Islands.
		for p in IslandRegistry.placements:
			var placement := p as IslandPlacement
			if placement == null or placement.def == null:
				continue
			var mpos := _world_to_map(placement.position)
			var r_px: float = placement.def.footprint_radius * (s.x / WORLD_SIZE)
			r_px = maxf(r_px, 3.0)
			var col := _island_color(placement.def)
			draw_circle(mpos, r_px, col)
			draw_arc(mpos, r_px, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.0)
			if placement.def.display_name != "":
				var label_pos := mpos + Vector2(r_px + 4.0, 4.0)
				draw_string(font, label_pos, placement.def.display_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

		# Player marker.
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null and is_instance_valid(player):
			var ppos := _world_to_map(player.global_position)
			# Forward in Godot 3D is -Z. Project to XZ then to map (which flips Z to +Y down).
			var fwd3 := -player.global_transform.basis.z
			var fwd2 := Vector2(fwd3.x, fwd3.z).normalized()
			if fwd2.length() < 0.001:
				fwd2 = Vector2(0, -1)
			var angle := fwd2.angle()
			_draw_player_arrow(ppos, angle)

	func _draw_player_arrow(center: Vector2, angle: float) -> void:
		var size_px := 10.0
		var tri := PackedVector2Array([
			Vector2( size_px, 0),
			Vector2(-size_px * 0.7,  size_px * 0.6),
			Vector2(-size_px * 0.7, -size_px * 0.6),
		])
		var xform := Transform2D(angle, center)
		var out := PackedVector2Array()
		for v in tri:
			out.append(xform * v)
		draw_colored_polygon(out, Color(1.0, 0.9, 0.2))
		draw_polyline(PackedVector2Array([out[0], out[1], out[2], out[0]]),
			Color(0, 0, 0, 0.8), 1.0)

	func _world_to_map(world: Vector3) -> Vector2:
		var nx := (world.x + WORLD_SIZE * 0.5) / WORLD_SIZE
		var nz := (world.z + WORLD_SIZE * 0.5) / WORLD_SIZE
		return Vector2(nx, nz) * size

	func _island_color(def: IslandDef) -> Color:
		if def.biome != null:
			var c: Color = def.biome.terrain_albedo
			c.a = 1.0
			return c
		return Color(0.4, 0.6, 0.3)
