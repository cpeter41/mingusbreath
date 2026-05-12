extends Node3D
## Dev sandbox — not shipped. Removed when real spawn flow lands.

const PlayerScene := preload("res://scenes/player/Player.tscn")
const DummyScene  := preload("res://scenes/enemies/TargetDummy.tscn")
const HuskScene   := preload("res://scenes/enemies/Husk.tscn")
const HUDScript   := preload("res://scripts/ui/hud.gd")
const BoatScript  := preload("res://scripts/ships/boat.gd")

func _ready() -> void:
	_add_lighting()
	_build_island()
	_add_water()
	_spawn_player()
	_spawn_dummies()
	_spawn_husks()
	_spawn_boat()
	_spawn_hud()
	_connect_debug_signals()


func _build_island() -> void:
	var data := IslandGenerator.generate(GameState.world_seed, 120, 8.0)

	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = data["mesh"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.55, 0.18)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain.material_override = mat
	add_child(terrain)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var col := CollisionShape3D.new()
	col.shape = data["collider"]
	body.add_child(col)
	add_child(body)

	var shore := StaticBody3D.new()
	shore.name = "ShoreWall"
	shore.collision_layer = 8  # boat-only layer; player mask 1 won't detect it
	shore.collision_mask = 0
	var shore_col := CollisionShape3D.new()
	shore_col.shape = data["shore_wall"]
	shore.add_child(shore_col)
	add_child(shore)


func _add_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "WaterPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.28, 0.72)
	water.material_override = mat
	water.position.y = Ocean.WATER_BASE_Y
	add_child(water)


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.65, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.5)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	add_child(env_node)


func _spawn_player() -> void:
	var player := PlayerScene.instantiate()
	player.position = Vector3(0.0, 15.0, 0.0)
	add_child(player)


func _spawn_dummies() -> void:
	await get_tree().physics_frame
	var h := _sample_terrain(0.0, -6.0)
	var dummy := DummyScene.instantiate()
	dummy.position = Vector3(0.0, h, -6.0)
	add_child(dummy)


func _spawn_husks() -> void:
	await get_tree().physics_frame
	var xz_offsets := [
		Vector2( 8.0,  0.0),
		Vector2(-8.0,  0.0),
	]
	for xz in xz_offsets:
		var h := _sample_terrain(xz.x, xz.y)
		var husk := HuskScene.instantiate()
		husk.position = Vector3(xz.x, h + 0.9, xz.y)
		add_child(husk)


func _sample_terrain(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 50.0, z), Vector3(x, -10.0, z)
	)
	query.collision_mask = 1  # terrain StaticBody3D is on default layer 1
	var result := space.intersect_ray(query)
	return result.position.y if result else 0.0


func _spawn_hud() -> void:
	var hud := HUDScript.new()
	hud.name = "PlayerHUD"
	add_child(hud)


func _spawn_boat() -> void:
	var boat := BoatScript.new()
	boat.name = "Boat"
	boat.position = Vector3(62.0, Ocean.WATER_BASE_Y, 0.0)
	add_child(boat)


func _connect_debug_signals() -> void:
	EventBus.damage_dealt.connect(
		func(atk, _tgt, wpn, skl, amt):
			#print("[damage_dealt] %.1f  weapon=%s  skill=%s" % [amt, wpn, skl])
			pass
	)
	EventBus.enemy_killed.connect(
		func(enemy_id, _killer):
			#print("[enemy_killed] %s" % enemy_id)
			pass
	)
