class_name ZoneDebug
extends Node3D

@export var enabled: bool = false
@export var resolution: int = 128
@export var y_offset: float = 2.0
@export var alpha: float = 0.6

var _plane: MeshInstance3D = null


const HIT_MARKER_SIZE := 0.4
const HIT_MARKER_LIFETIME := 3.0


func _ready() -> void:
	visible = enabled
	ZoneMap.set_debug_visible(enabled)
	ZoneMap.debug_toggled.connect(_on_toggle)
	# Debug projectile-hit markers gate on ZoneMap.debug_visible inside the
	# handler, not on `enabled`, so toggling F2 immediately starts/stops them.
	EventBus.projectile_hit_debug.connect(_on_projectile_hit_debug)
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


## F2-gated. Drops a red wireframe cube at the impact point that auto-frees
## after HIT_MARKER_LIFETIME seconds. Parented to self (a Node3D in World) so
## the marker survives this script's `visible` toggling — visibility of the
## zone overlay plane shouldn't hide the hit markers.
func _on_projectile_hit_debug(pos: Vector3) -> void:
	if not ZoneMap.debug_visible:
		return
	var mi := _make_wire_cube(HIT_MARKER_SIZE, Color(1.0, 0.1, 0.1, 1.0))
	add_child(mi)
	mi.global_position = pos
	# visible flag is owned by self (toggled with F2). Force this marker on
	# regardless so toggling the zone plane off doesn't hide hit markers.
	mi.visible = true
	get_tree().create_timer(HIT_MARKER_LIFETIME).timeout.connect(mi.queue_free)


func _make_wire_cube(size: float, color: Color) -> MeshInstance3D:
	var s := size * 0.5
	var verts := PackedVector3Array([
		Vector3(-s,-s,-s), Vector3( s,-s,-s),
		Vector3( s,-s,-s), Vector3( s, s,-s),
		Vector3( s, s,-s), Vector3(-s, s,-s),
		Vector3(-s, s,-s), Vector3(-s,-s,-s),
		Vector3(-s,-s, s), Vector3( s,-s, s),
		Vector3( s,-s, s), Vector3( s, s, s),
		Vector3( s, s, s), Vector3(-s, s, s),
		Vector3(-s, s, s), Vector3(-s,-s, s),
		Vector3(-s,-s,-s), Vector3(-s,-s, s),
		Vector3( s,-s,-s), Vector3( s,-s, s),
		Vector3( s, s,-s), Vector3( s, s, s),
		Vector3(-s, s,-s), Vector3(-s, s, s),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true   # outline visible through walls — debug
	mi.material_override = mat
	return mi
