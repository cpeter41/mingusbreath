class_name MainlandTerrain
extends Node3D

const SIZE_M := 800
const MAX_HEIGHT_M := 40.0
const SEED := 0x4D41494E  # "MAIN"

# Cached across instances — mainland is single-slot, but cache is harmless if scene reloads.
static var _cache: Dictionary = {}


func _ready() -> void:
	var data := _get_or_generate()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.65, 0.30)
	mat.roughness = 0.85

	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = data["mesh"]
	terrain.material_override = mat
	add_child(terrain)

	var body := StaticBody3D.new()
	body.name = "Body"
	add_child(body)

	var heightmap_shape := CollisionShape3D.new()
	heightmap_shape.name = "HeightmapShape"
	heightmap_shape.shape = data["collider"]
	body.add_child(heightmap_shape)

	# Shore wall on its own body, boat-only layer (8). Player mask=1 ignores it.
	var shore_body := StaticBody3D.new()
	shore_body.name = "ShoreBody"
	shore_body.collision_layer = 8
	shore_body.collision_mask = 0
	add_child(shore_body)

	var wall_shape := CollisionShape3D.new()
	wall_shape.name = "ShoreWallShape"
	wall_shape.shape = data["shore_wall"]
	shore_body.add_child(wall_shape)

	var anchor := Node3D.new()
	anchor.name = "SpawnAnchor"
	anchor.position = Vector3(0, MAX_HEIGHT_M + 5.0, 0)
	add_child(anchor)


static func _get_or_generate() -> Dictionary:
	if _cache.is_empty():
		_cache = IslandGenerator.generate(SEED, SIZE_M, MAX_HEIGHT_M)
	return _cache
