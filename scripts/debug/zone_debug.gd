class_name ZoneDebug
extends Node3D

@export var enabled: bool = false
@export var resolution: int = 128
@export var y_offset: float = 2.0
@export var alpha: float = 0.6

var _plane: MeshInstance3D = null


func _ready() -> void:
	visible = enabled
	ZoneMap.set_debug_visible(enabled)
	ZoneMap.debug_toggled.connect(_on_toggle)
	if not enabled:
		return
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2:
			ZoneMap.set_debug_visible(not ZoneMap.debug_visible)


func _on_toggle(v: bool) -> void:
	visible = v
	if v and _plane == null:
		_build()


func _build() -> void:
	var world_size: float = IslandRegistry.WORLD_SIZE_M

	var img := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	var step := world_size / float(resolution)
	var origin := -world_size * 0.5 + step * 0.5
	for iz in resolution:
		for ix in resolution:
			var wx := origin + ix * step
			var wz := origin + iz * step
			var zone := ZoneMap.get_zone(Vector3(wx, 0.0, wz))
			var c: Color = zone.def.debug_color if zone != null else Color.MAGENTA
			c.a = alpha
			img.set_pixel(ix, iz, c)

	var tex := ImageTexture.create_from_image(img)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(world_size, world_size)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_plane = MeshInstance3D.new()
	_plane.mesh = mesh
	_plane.material_override = mat
	_plane.position = Vector3(0.0, y_offset, 0.0)
	add_child(_plane)
