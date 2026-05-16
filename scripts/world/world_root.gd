class_name WorldRoot
extends Node3D

var _local_player: Node3D = null
var _initialized_local: bool = false


func _ready() -> void:
	# Host loads world-state saveables FIRST — GameState.world_seed must be
	# restored before compute_placements() runs, or islands generate from the
	# default seed and land in the wrong spots.
	if multiplayer.is_server():
		SaveSystem.load_or_init()

	IslandRegistry.compute_placements()
	var container := $IslandContainer as Node3D
	WorldStream.set_container(container)
	TimeOfDay.set_sun($Sun as DirectionalLight3D)
	TimeOfDay.set_world_environment(($WorldEnv as WorldEnvironment).environment)

	var hud := HUD.new()
	hud.name = "PlayerHUD"
	add_child(hud)

	# Listen for player spawns; the spawner adds them under Players.
	($Players as Node).child_entered_tree.connect(_on_player_added)

	# Autosave at daybreak instead of on a fixed timer.
	EventBus.time_phase_changed.connect(_on_time_phase_changed)

	# Tell NetworkManager we're ready so the server can spawn players into us.
	NetworkManager.register_world_root(self)


func _on_player_added(p: Node) -> void:
	# MultiplayerSynchronizer's authority is set on add_child; wait one frame
	# so all child-added _ready callbacks have run before we check ownership.
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	if p.get_multiplayer_authority() != multiplayer.get_unique_id():
		return  # not our local player
	if _initialized_local:
		return
	_initialized_local = true
	_local_player = p as Node3D

	# Load this peer's profile (skills, inventory, player loadout/position)
	# before world_loaded fires, so the starter-loadout grant sees restored
	# items and the player applies its saved spawn position.
	ProfileSave.load_or_init()

	WorldStream.set_player(_local_player)  # emits world_loaded after first batch
	($OceanFollower as OceanFollower).set_target(_local_player)


## Autosave whenever dawn breaks. Fires on every peer; gating below keeps the
## world save host-only while every peer still saves its own profile.
func _on_time_phase_changed(phase: int) -> void:
	if phase != TimeOfDay.Phase.DAWN:
		return
	if _local_player == null or not _local_player.get("_world_ready"):
		return
	ProfileSave.save()            # every peer autosaves its own profile
	if multiplayer.is_server():
		NetworkManager.record_all_player_positions()
		SaveSystem.save()         # host also autosaves the world


func _exit_tree() -> void:
	if not _initialized_local:
		NetworkManager._world_root = null
		return
	ProfileSave.save()            # every peer saves its own profile
	if multiplayer.is_server():
		NetworkManager.record_all_player_positions()
		GameState.last_played_at = int(Time.get_unix_time_from_system())
		SaveSystem.save()
	NetworkManager._world_root = null
