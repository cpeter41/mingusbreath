class_name Moon
extends MeshInstance3D

const DIST      := 900.0
const DISC_SIZE := Vector2(55.0, 55.0)


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = DISC_SIZE
	mesh = quad

	var mat := StandardMaterial3D.new()
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture  = _make_moon_texture()
	mat.albedo_color    = Color(0.85, 0.90, 1.0)
	mat.no_depth_test   = false
	mat.render_priority = -1
	material_override   = mat


func _process(_delta: float) -> void:
	var moon := get_parent() as DirectionalLight3D
	if moon == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var moon_dir := moon.global_transform.basis.z.normalized()
	visible = moon_dir.y > -0.05
	global_position = cam.global_position + moon_dir * DIST


func _make_moon_texture() -> ImageTexture:
	var sz  := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c   := sz * 0.5
	for y in sz:
		for x in sz:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var d  := sqrt(dx * dx + dy * dy)
			var a  := 1.0 - smoothstep(0.78, 0.96, d)
			img.set_pixel(x, y, Color(0.92, 0.95, 1.0, a))
	return ImageTexture.create_from_image(img)
