class_name Sun
extends DirectionalLight3D

const DISC_DIST    := 900.0
const DISC_SIZE    := Vector2(80.0, 80.0)
const HORIZON_FADE := 0.1

var _max_energy: float = 1.0
var _disc: MeshInstance3D


func _ready() -> void:
	_max_energy = light_energy
	_disc = _build_disc()
	add_child(_disc)


func _process(_dt: float) -> void:
	var m := fmod(TimeOfDay.game_minutes, TimeOfDay.MINUTES_PER_DAY)
	rotation.x = TAU * m / TimeOfDay.MINUTES_PER_DAY + PI / 2.0
	light_energy = _max_energy * _horizon_factor()
	_update_disc()


func _horizon_factor() -> float:
	var elev: float = global_transform.basis.z.y
	return clampf(elev / HORIZON_FADE, 0.0, 1.0)


func _update_disc() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dir := global_transform.basis.z.normalized()
	_disc.visible = dir.y > -0.05
	_disc.global_position = cam.global_position + dir * DISC_DIST


func _build_disc() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = DISC_SIZE
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture  = _make_disc_texture()
	mat.albedo_color    = Color(1.0, 0.95, 0.70)
	mat.render_priority = -1
	mi.material_override = mat
	return mi


func _make_disc_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := sz * 0.5
	for y in sz:
		for x in sz:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var a := 1.0 - smoothstep(0.55, 1.0, d)
			img.set_pixel(x, y, Color(1.0, 0.97, 0.80, a))
	return ImageTexture.create_from_image(img)
