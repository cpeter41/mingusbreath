extends CharacterBody3D
# Owner-authoritative player.
# Movement runs on the owning client. Position, rotation, hp, stamina replicate to
# all peers via MultiplayerSynchronizer. Damage is requested via RPC and applied
# on the owner. Camera/input attach only on the owning peer.

const MOUSE_SENSITIVITY := 0.003
const SWORD_SCENE   := preload("res://scenes/weapons/Sword.tscn")
const SHIELD_SCENE  := preload("res://scenes/weapons/Shield.tscn")
const BOAT_SCENE    := preload("res://scenes/ships/Boat.tscn")
const RESPAWN_FALLBACK_Y := 15.0
const BOAT_SPAWN_DIST := 8.0

@export var max_hp: float      = 100.0
@export var max_stamina: float = 150.0

# Replicated via MultiplayerSynchronizer. Setters re-emit EventBus signals
# only on the owning peer so each peer's HUD reads its own local player.
var hp: float = 0.0:
	set(v):
		hp = v
		if is_inside_tree() and is_multiplayer_authority():
			EventBus.player_hp_changed.emit(hp, max_hp)
var stamina: float = 0.0:
	set(v):
		stamina = v
		if is_inside_tree() and is_multiplayer_authority():
			EventBus.player_stamina_changed.emit(stamina, max_stamina)
var on_boat: bool      = false
var is_blocking: bool  = false
var is_parrying: bool  = false

# Replicated visual flags. Owner sets these from inventory contents; all peers
# spawn/free the Sword/Shield mount nodes based on flag transitions. Inventory
# contents themselves are not replicated — only the visible loadout state is.
var has_sword: bool = false:
	set(v):
		has_sword = v
		_update_sword_visual()
var has_shield: bool = false:
	set(v):
		var was := has_shield
		has_shield = v
		_update_shield_visual()
		if not v and was and is_inside_tree() and is_multiplayer_authority() and is_blocking and actionSM != null:
			actionSM.transition_to("idle")

@export var speed: float = 5.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _stamina_regen_timer: float = 999.0
var _world_ready: bool = false  # true after _on_world_loaded places the player
var _has_pending_pos: bool = false
var _pending_pos: Vector3 = Vector3.ZERO
var _pending_rot_y: float = 0.0

@onready var camera_pivot: Node3D  = $CameraPivot
@onready var movementSM: Node      = $MovementStateMachine
@onready var actionSM: Node        = $ActionStateMachine
@onready var inventory: Inventory  = $Inventory
@onready var weapon_mount: Node3D  = $WeaponMount
@onready var shield_mount: Node3D  = $ShieldMount
@onready var hurtbox: Area3D       = $Hurtbox


func _ready() -> void:
	# Authority is encoded in the node name "Player_<peer_id>" by NetworkManager.
	# Each peer derives the same authority locally — MultiplayerSpawner does NOT
	# replicate set_multiplayer_authority calls, so name parsing is the canonical
	# place to set it.
	var parts := name.split("_")
	if parts.size() == 2 and parts[0] == "Player":
		set_multiplayer_authority(int(parts[1]), true)

	hp = max_hp
	stamina = max_stamina
	inventory.changed.connect(_on_inventory_changed)
	EventBus.world_loaded.connect(_on_world_loaded, CONNECT_ONE_SHOT)

	# Only the owning peer drives input, camera, and physics for this player.
	# Non-owner peers see a replicated ghost driven by the MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		# Remote ghost: keep collision off the player's own move_and_slide path
		# but allow incoming hitboxes to still detect this body.
		set_physics_process(false)
		return

	add_to_group("player")
	Controls.capture_mouse()
	Controls.pause_pressed.connect(_on_pause_pressed)
	Controls.reset_pressed.connect(_on_reset_pressed)
	Controls.spawn_boat_pressed.connect(_on_spawn_boat_pressed)
	Controls.mouse_look.connect(_on_mouse_look)
	$CameraPivot/SpringArm3D/Camera3D.make_current()
	EventBus.player_hp_changed.emit.call_deferred(hp, max_hp)
	EventBus.player_stamina_changed.emit.call_deferred(stamina, max_stamina)
	# Inventory persists to this peer's local profile. Player POSITION lives in
	# the host's world save (PlayerStore) — the host pushes it via the
	# set_spawn_position RPC when this player spawns.
	ProfileSave.register(inventory, "Inventory")


func _on_inventory_changed() -> void:
	# Owner's inventory is the source of truth. Update the replicated visual
	# flags; setters spawn/free the mount nodes on every peer.
	if not is_multiplayer_authority():
		return
	has_sword = inventory.count_of(&"sword") > 0
	has_shield = inventory.count_of(&"shield") > 0


func _update_sword_visual() -> void:
	if not is_inside_tree() or weapon_mount == null:
		return
	var existing := weapon_mount.get_node_or_null("Sword")
	if has_sword and existing == null:
		weapon_mount.add_child(SWORD_SCENE.instantiate())
	elif not has_sword and existing != null:
		existing.queue_free()


func _update_shield_visual() -> void:
	if not is_inside_tree() or shield_mount == null:
		return
	var existing := shield_mount.get_node_or_null("Shield")
	if has_shield and existing == null:
		shield_mount.add_child(SHIELD_SCENE.instantiate())
	elif not has_shield and existing != null:
		existing.queue_free()


func take_pickup(item_id: StringName, count: int) -> void:
	inventory.add(item_id, count)
	EventBus.item_picked_up.emit(item_id, count)


## Public damage entry. Local callers (server-side enemies, this player's own
## combat code) pass `source` as a Node. Cross-peer calls go through
## `take_damage_rpc` which takes a NodePath and forwards here.
func take_damage(amount: float, source = null) -> void:
	if not is_multiplayer_authority():
		# Reroute to owner.
		var src_path: NodePath = source.get_path() if source is Node else NodePath()
		rpc_id(get_multiplayer_authority(), "take_damage_rpc", amount, src_path)
		return
	if is_parrying:
		EventBus.player_parried.emit(source)
		return
	if is_blocking:
		var cost := amount * 0.5
		if consume_stamina(cost):
			amount *= 0.2
		# stamina too low — block fails, full damage applies
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		die()


@rpc("any_peer", "reliable")
func take_damage_rpc(amount: float, source_path: NodePath) -> void:
	if not is_multiplayer_authority():
		return
	var src: Node = get_node_or_null(source_path) if source_path != NodePath() else null
	take_damage(amount, src)


func consume_stamina(amount: float) -> bool:
	if not is_multiplayer_authority():
		return false
	if stamina < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	_stamina_regen_timer = 0.0
	return true


func die() -> void:
	if not is_multiplayer_authority():
		return
	EventBus.player_died.emit()
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(self):
		return
	respawn()


func respawn() -> void:
	if not is_multiplayer_authority():
		return
	global_position = _mainland_spawn_point() + _spawn_offset_for_peer(get_multiplayer_authority())
	hp = max_hp
	stamina = max_stamina
	_stamina_regen_timer = 999.0
	EventBus.player_respawned.emit()


func _on_pause_pressed() -> void:
	Controls.toggle_mouse_capture()


func _on_reset_pressed() -> void:
	SaveSystem.disable_save()
	SaveSystem.delete_save()
	ProfileSave.disable_save()
	ProfileSave.delete_profile()
	get_tree().paused = false
	Controls.capture_mouse()
	if NetworkManager.is_offline():
		get_tree().reload_current_scene()
	else:
		# Reloading a networked scene breaks the spawn contract — drop to lobby.
		NetworkManager.disconnect_all()
		get_tree().change_scene_to_file("res://scenes/ui/LobbyMenu.tscn")


func _on_spawn_boat_pressed() -> void:
	if on_boat:
		return
	_try_spawn_boat()


func _on_mouse_look(delta: Vector2) -> void:
	if on_boat:
		return
	rotate_y(-delta.x * MOUSE_SENSITIVITY)
	camera_pivot.rotate_x(-delta.y * MOUSE_SENSITIVITY)
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0)
	)


func _physics_process(delta: float) -> void:
	_regen_stamina(delta)
	if on_boat:
		return  # Boat owns transform; skip movement, action, and move_and_slide.
	movementSM.physics_update(delta)
	actionSM.physics_update(delta)
	move_and_slide()


func _regen_stamina(delta: float) -> void:
	_stamina_regen_timer += delta
	if _stamina_regen_timer > 0.5 and stamina < max_stamina:
		stamina = minf(max_stamina, stamina + 15.0 * delta)
		EventBus.player_stamina_changed.emit(stamina, max_stamina)




func _try_spawn_boat() -> void:
	var fwd := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()
	var spawn_pos := global_position + fwd * BOAT_SPAWN_DIST
	spawn_pos.y = 0.0
	if WorldStream.get_placement_enclosing(spawn_pos) != null:
		return
	var existing := BoatManager.get_existing_boat()
	if existing != null:
		existing.global_position = spawn_pos
		existing.rotation.y = rotation.y
		return
	var boat := BOAT_SCENE.instantiate() as Boat
	boat.rotation.y = rotation.y
	get_parent().add_child(boat)
	boat.global_position = spawn_pos
	BoatManager.register_boat(boat)


const SPAWN_RING_RADIUS := 3.0
const SPAWN_SLOTS := 4


func _on_world_loaded() -> void:
	if not is_multiplayer_authority():
		_world_ready = true
		return
	# Grant starter loadout once. Idempotent so it survives save/load round-trips.
	if inventory.count_of(&"sword") == 0:
		inventory.add(&"sword", 1)
	if inventory.count_of(&"shield") == 0:
		inventory.add(&"shield", 1)

	# Saved position from the profile wins; otherwise spawn at the mainland
	# anchor offset to this peer's spawn slot.
	if _has_pending_pos:
		global_position = _pending_pos
		rotation.y = _pending_rot_y
	else:
		global_position = _mainland_spawn_point() + _spawn_offset_for_peer(get_multiplayer_authority())
	velocity = Vector3.ZERO
	_world_ready = true


## Sets the spawn position. If the world is already loaded, teleports
## immediately; otherwise _on_world_loaded picks it up. Host calls this on its
## own player directly and RPCs guests via set_spawn_position.
func apply_spawn_position(pos: Vector3, rot_y: float) -> void:
	_pending_pos = pos
	_pending_rot_y = rot_y
	_has_pending_pos = true
	if _world_ready and is_multiplayer_authority():
		global_position = pos
		rotation.y = rot_y
		velocity = Vector3.ZERO


@rpc("any_peer", "reliable")
func set_spawn_position(pos: Vector3, rot_y: float) -> void:
	# Only the host assigns spawn positions. (This Player's multiplayer
	# authority is the owning guest, so @rpc("authority") would reject the
	# host's call — hence any_peer + an explicit server-sender check.)
	if multiplayer.get_remote_sender_id() != 1:
		return
	apply_spawn_position(pos, rot_y)


## Deterministic per-peer offset around mainland anchor. Each peer arrives at a
## distinct slot on a small ring so capsules don't overlap and shove each other.
func _spawn_offset_for_peer(peer_id: int) -> Vector3:
	var idx := peer_id % SPAWN_SLOTS
	var angle := TAU * float(idx) / float(SPAWN_SLOTS)
	return Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING_RADIUS


func _mainland_spawn_point() -> Vector3:
	var mp := IslandRegistry.get_mainland_placement()
	if mp == null:
		return Vector3(0.0, RESPAWN_FALLBACK_Y, 0.0)
	var inst := WorldStream.get_far_instance(mp.runtime_id)
	if inst != null:
		var anchor := inst.get_node_or_null("SpawnAnchor") as Node3D
		if anchor != null:
			return anchor.global_position
	return mp.position + Vector3(0.0, RESPAWN_FALLBACK_Y, 0.0)
