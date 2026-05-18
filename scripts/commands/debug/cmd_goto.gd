extends ChatCommand

const RAYCAST_HEIGHT   := 500.0  # cast from this Y downward
const WATER_LEVEL_Y    := 0.0    # fallback when no terrain under target point
const TERRAIN_OFFSET_Y := 0.1    # nudge above hit surface so player doesn't clip

func get_name() -> StringName:
	return &"goto"

func get_category() -> StringName:
	return &"debug"

func execute(args: Array) -> String:
	if args.size() < 2:
		return "Usage: /goto <x> <z>  |  /goto <x> <y> <z>"

	var tree := Engine.get_main_loop() as SceneTree
	var player := tree.get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return "No local player found."

	var x := float(args[0])

	if args.size() >= 3:
		# Exact Godot coords (x, y, z) — y is vertical.
		var y := float(args[1])
		var z := float(args[2])
		player.global_position = Vector3(x, y, z)
		player.velocity = Vector3.ZERO
		return "Teleported to (%.1f, %.1f, %.1f)." % [x, y, z]

	# Two-arg form: x and z. Raycast straight down to find terrain surface.
	# Falls back to water level (y=0) if nothing is hit.
	var z := float(args[1])
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, RAYCAST_HEIGHT, z),
		Vector3(x, -RAYCAST_HEIGHT, z)
	)
	query.collision_mask = 1          # World layer only — skip hitboxes, ghosts, etc.
	query.exclude = [player.get_rid()]
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)

	var y: float
	if result.is_empty():
		y = WATER_LEVEL_Y
	else:
		y = (result["position"] as Vector3).y + TERRAIN_OFFSET_Y

	player.global_position = Vector3(x, y, z)
	player.velocity = Vector3.ZERO
	return "Teleported to (%.1f, %.1f, %.1f)." % [x, y, z]
