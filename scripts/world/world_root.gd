class_name WorldRoot
extends Node3D

const AUTOSAVE_INTERVAL := 60.0

var _autosave_timer: float = 0.0


func _ready() -> void:
	# Strict order — do not reorder.+
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

func _process(delta: float) -> void:
	if not ($Player as Node3D).get("_world_ready"):
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		SaveSystem.save()


func _exit_tree() -> void:
	GameState.last_played_at = int(Time.get_unix_time_from_system())
	SaveSystem.save()
