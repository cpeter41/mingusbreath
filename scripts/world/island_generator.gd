class_name IslandGenerator

## Pure function — deterministic for same (seed, size_m, max_height_m).
## No randf(). Used by test island now; reused by chunk streaming later.
static func generate(seed: int, size_m: int, max_height_m: float) -> Dictionary:
	var resolution := size_m + 1  # vertices per side; cells = size_m x size_m

	var noise_c := FastNoiseLite.new()
	noise_c.seed = seed
	noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_c.frequency = 0.006  # ~167 unit period → gentle continent roll

	var noise_d := FastNoiseLite.new()
	noise_d.seed = seed ^ 0x9E3779B9  # distinct seed, same determinism
	noise_d.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_d.frequency = 0.035  # ~29 unit period → rocky surface detail

	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)

	for z in resolution:
		for x in resolution:
			var nx := float(x) / float(resolution - 1)  # [0, 1]
			var nz := float(z) / float(resolution - 1)  # [0, 1]
			var dx := nx - 0.5
			var dz := nz - 0.5
			var dist := sqrt(dx * dx + dz * dz)
			# Island falloff: full within r≈0.3, coast at r≈0.5, sea beyond
			var falloff := 1.0 - smoothstep(0.3, 0.5, dist)
			var c := (noise_c.get_noise_2d(float(x), float(z)) + 1.0) * 0.5
			var d := (noise_d.get_noise_2d(float(x), float(z)) + 1.0) * 0.5
			heights[x + z * resolution] = (c * 0.7 + d * 0.3) * falloff * max_height_m

	return {
		"mesh": _build_mesh(heights, resolution),
		"collider": _build_collider(heights, resolution),
	}


static func _build_mesh(heights: PackedFloat32Array, resolution: int) -> ArrayMesh:
	var half := (resolution - 1) * 0.5
	var verts   := PackedVector3Array(); verts.resize(resolution * resolution)
	var normals := PackedVector3Array(); normals.resize(resolution * resolution)
	var uvs     := PackedVector2Array(); uvs.resize(resolution * resolution)
	var indices := PackedInt32Array()

	for z in resolution:
		for x in resolution:
			var i := x + z * resolution
			verts[i]   = Vector3(float(x) - half, heights[i], float(z) - half)
			normals[i] = _normal_at(heights, resolution, x, z)
			uvs[i]     = Vector2(float(x) / (resolution - 1), float(z) / (resolution - 1))

	# CW winding from above = front face in Godot 4's Vulkan renderer
	for z in (resolution - 1):
		for x in (resolution - 1):
			var i := x + z * resolution
			indices.append(i);               indices.append(i + 1)
			indices.append(i + resolution);  indices.append(i + 1)
			indices.append(i + resolution + 1); indices.append(i + resolution)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _build_collider(heights: PackedFloat32Array, resolution: int) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = resolution
	shape.map_depth = resolution
	shape.map_data  = heights
	return shape


static func _normal_at(heights: PackedFloat32Array, resolution: int, x: int, z: int) -> Vector3:
	var xl := heights[max(x - 1, 0)             + z * resolution]
	var xr := heights[min(x + 1, resolution - 1) + z * resolution]
	var zb := heights[x + max(z - 1, 0)              * resolution]
	var zf := heights[x + min(z + 1, resolution - 1) * resolution]
	# Finite-difference gradient: Y=2 balances 1-unit XZ steps
	return Vector3(xl - xr, 2.0, zb - zf).normalized()
