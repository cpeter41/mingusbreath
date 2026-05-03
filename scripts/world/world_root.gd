class_name WorldRoot
extends Node3D


func _ready() -> void:
	# Strict order — do not reorder.
	SaveSystem.load_or_init()
	IslandRegistry.compute_placements()

	var container := $IslandContainer as Node3D
	var player    := $Player as Node3D

	WorldStream.set_container(container)
	WorldStream.set_player(player)   # triggers first-batch load + world_loaded emit

	($OceanFollower as OceanFollower).set_target(player)

	TimeOfDay.set_sun($Sun as DirectionalLight3D)
	TimeOfDay.set_world_environment(($WorldEnv as WorldEnvironment).environment)

	var hud := HUD.new()
	hud.name = "PlayerHUD"
	add_child(hud)


func _exit_tree() -> void:
	GameState.last_played_at = int(Time.get_unix_time_from_system())
	SaveSystem.save()
