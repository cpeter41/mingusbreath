class_name Sun
extends MeshInstance3D

const DIST      := 900.0
const DISC_SIZE := Vector2(80.0, 80.0)


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = DISC_SIZE
	mesh = quad

	var mat := StandardMaterial3D.new()
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture  = _make_sun_texture()
	mat.albedo_color    = Color(1.0, 0.95, 0.70)
	mat.no_depth_test   = false
	mat.render_priority = -1
	material_override   = mat


func _process(_delta: float) -> void:
	var sun := get_parent() as DirectionalLight3D
	if sun == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var sun_dir := sun.global_transform.basis.z.normalized()
	visible = sun_dir.y > -0.05
	global_position = cam.global_position + sun_dir * DIST


func _make_sun_texture() -> ImageTexture:
	var sz  := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c   := sz * 0.5
	for y in sz:
		for x in sz:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var d  := sqrt(dx * dx + dy * dy)
			var a  := 1.0 - smoothstep(0.55, 1.0, d)
			img.set_pixel(x, y, Color(1.0, 0.97, 0.80, a))
	return ImageTexture.create_from_image(img)
