class_name WorldRoot
extends Node3D

const AUTOSAVE_INTERVAL := 60.0

var _autosave_timer: float = 0.0
var _local_player: Node3D = null
var _initialized_local: bool = false


func _ready() -> void:
	# Static world setup that doesn't need a player ref.
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

	# Host loads world-state saveables (TimeOfDay, GameState, SkillManager, etc.)
	# BEFORE players spawn — so when NetworkManager broadcasts time-of-day to
	# joining guests, it sends the loaded value instead of the default zero.
	# Player position save/load is deferred to Phase 8; players spawn at mainland.
	if multiplayer.is_server():
		SaveSystem.load_or_init()

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

	WorldStream.set_player(_local_player)  # emits world_loaded after first batch
	($OceanFollower as OceanFollower).set_target(_local_player)


func _process(delta: float) -> void:
	if _local_player == null or not _local_player.get("_world_ready"):
		return
	if not multiplayer.is_server():
		return  # only host autosaves
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		SaveSystem.save()


func _exit_tree() -> void:
	NetworkManager._world_root = null
	if not multiplayer.is_server():
		return
	GameState.last_played_at = int(Time.get_unix_time_from_system())
	SaveSystem.save()
