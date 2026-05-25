extends CharacterBody3D
# Owner-authoritative player.
# Movement runs on the owning client. Position, rotation, hp, stamina replicate to
# all peers via MultiplayerSynchronizer. Damage is requested via RPC and applied
# on the owner. Camera/input attach only on the owning peer.

const MOUSE_SENSITIVITY := 0.003
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

# Replicated movement-anim state name (owner authority). Owner's MovementSM
# writes this on every transition; the setter fires the matching clip on every
# peer so remote ghosts animate in lockstep with the owner. Stored as the
# lowercase movement state name ("idle", "run", "sprint", "jump", "fall", "swim").
#
# Defaults match the Monk rig's clip names. Each class can override via its
# ClassDef.anim_overrides dictionary (merged in _apply_character_model) — for
# example Rogue uses "Dagger_Attack" instead of "Attack". Stored as a var, not
# a const, so the merge can mutate it per-instance.
var anim_for_state: Dictionary = {
	&"idle":   &"Idle",
	&"run":    &"Walk",
	&"sprint": &"Run",
	&"jump":   &"Idle",
	&"fall":   &"Idle",
	&"swim":   &"Idle",
	# Action-state clips. The attack/dodge action-states push these onto
	# anim_state; they take priority over locomotion for their duration
	# (see MovementSM._push_anim).
	&"attack": &"Attack",
	&"dodge":  &"Roll",
}
var anim_state: StringName = &"idle":
	set(v):
		anim_state = v
		_play_anim(v)

# Replicated via the spawn packet (SRC_player properties/8, spawn=true, mode
# Never). Host sets this before add_child in NetworkManager._spawn_player_for_peer
# so every peer receives the correct class atomically with the node. The setter
# applies stats from ClassDef — safe to fire before _ready since it touches
# only plain fields, no @onready node access.
var class_id: StringName = ProfileSave.DEFAULT_CLASS_ID:
	set(v):
		class_id = v
		_apply_class()

@export var speed: float = 5.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Owning peer id, parsed from the node name in _enter_tree. Equals
# get_multiplayer_authority(). Defaults to 1 (host) until parsed.
var peer_id: int = 1

var _stamina_regen_timer: float = 999.0
var _world_ready: bool = false  # true after _on_world_loaded places the player
var _has_pending_pos: bool = false
var _pending_pos: Vector3 = Vector3.ZERO
var _pending_rot_y: float = 0.0
var _boat: Boat = null            # boat this player is mounted on, else null
var _saved_col_layer: int = 0
var _saved_col_mask: int = 0

@onready var camera_pivot: Node3D  = $CameraPivot
@onready var movementSM: Node      = $MovementStateMachine
@onready var actionSM: Node        = $ActionStateMachine
@onready var inventory: Inventory  = $Inventory
@onready var model_root: Node3D    = $Model
@onready var hurtbox: Area3D       = $Hurtbox
# Both populated by _apply_character_model() at spawn — they live inside the
# class's character_scene (varies per class) so they can't be @onready paths.
var weapon_mount: BoneAttachment3D = null
var anim_player: AnimationPlayer = null


## Applies stats from the resolved ClassDef. Touches only plain fields so it's
## safe to call from the class_id setter (which may fire before _ready, before
## @onready vars are resolved). Idempotent.
func _apply_class() -> void:
	var cdef := ClassRegistry.resolve(class_id)
	if cdef == null:
		return
	max_hp = cdef.max_hp
	max_stamina = cdef.max_stamina
	speed = cdef.move_speed


## Grants the class's starting items, mirroring the old hardcoded sword+shield
## block: per-item count_of==0 guard, so a returning character (inventory
## already restored by ProfileSave.load_or_init()) is not double-granted.
## Authority-only — call site lives inside _on_world_loaded's is_authority branch.
func _apply_starting_inventory() -> void:
	var cdef := ClassRegistry.resolve(class_id)
	if cdef == null:
		return
	for entry in cdef.starting_inventory:
		if entry == null:
			continue
		var item_id: StringName = entry.item_id
		if item_id == &"":
			continue
		if inventory.count_of(item_id) == 0:
			inventory.add(item_id, entry.count)


func _play_anim(state: StringName) -> void:
	if anim_player == null:
		return
	var clip: StringName = anim_for_state.get(state, &"Idle")
	if anim_player.has_animation(String(clip)) and anim_player.current_animation != String(clip):
		anim_player.play(clip)


## Authority is encoded in the node name "Player_<peer_id>" by NetworkManager.
## Each peer derives the same authority locally — MultiplayerSpawner does NOT
## replicate set_multiplayer_authority calls, so name parsing is the canonical
## place to set it. MUST run in _enter_tree (not _ready): changing a
## MultiplayerSynchronizer's authority in _ready races the pending spawn and
## triggers "unable to process the pending spawn since it has no network ID".
func _enter_tree() -> void:
	var parts := name.split("_")
	if parts.size() == 2 and parts[0] == "Player":
		peer_id = int(parts[1])
		# If this fires, NetworkManager named the node incorrectly; authority will
		# default to the server and the owning client loses input control silently.
		assert(peer_id > 0, "Player name has invalid peer_id: " + name)
		set_multiplayer_authority(peer_id, true)


func _ready() -> void:
	# Apply class first so max_hp / max_stamina / speed reflect the class def
	# before hp / stamina latch onto them. Idempotent — also runs from the
	# class_id setter on guests when the spawn packet arrives.
	_apply_class()
	# Visual + combat side: needs @onready vars resolved, so it runs here in
	# _ready rather than from the class_id setter. Runs on every peer so remote
	# ghosts show the correct character / weapon / attack state.
	# Order matters: character must mount first to create the WeaponMount bone
	# attachment + locate the AnimationPlayer that the weapon and anim setter
	# depend on.
	_apply_character_model()
	_mount_class_weapon()
	_apply_attack_state()
	hp = max_hp
	stamina = max_stamina
	EventBus.world_loaded.connect(_on_world_loaded, CONNECT_ONE_SHOT)
	# Kick off the initial clip; setter fires for subsequent transitions and
	# replicated syncs, but the default value never triggers it.
	_play_anim(anim_state)

	# Only the owning peer drives input, camera, and physics for this player.
	# Non-owner peers see a replicated ghost driven by the MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		# Remote ghost: keep collision off the player's own move_and_slide path
		# but allow incoming hitboxes to still detect this body.
		set_physics_process(false)
		return

	add_to_group("player")
	Controls.capture_mouse()
	Controls.reset_pressed.connect(_on_reset_pressed)
	Controls.spawn_boat_pressed.connect(_on_spawn_boat_pressed)
	Controls.interact_pressed.connect(_on_interact_pressed)
	Controls.mouse_look.connect(_on_mouse_look)
	$CameraPivot/SpringArm3D/Camera3D.make_current()
	EventBus.player_hp_changed.emit.call_deferred(hp, max_hp)
	EventBus.player_stamina_changed.emit.call_deferred(stamina, max_stamina)
	# Inventory persists to this peer's local profile. Player POSITION lives in
	# the host's world save (PlayerStore) — the host pushes it via the
	# set_spawn_position RPC when this player spawns.
	ProfileSave.register(inventory, "Inventory")


## Instantiates the class's character_scene under model_root. Locates the
## Skeleton3D + AnimationPlayer inside it, creates a "Weapon.R" BoneAttachment3D
## for the weapon mount, and merges the class's anim_overrides into
## anim_for_state. Runs on every peer so remote ghosts render the correct body.
func _apply_character_model() -> void:
	if model_root == null:
		return
	var cdef := ClassRegistry.resolve(class_id)
	if cdef == null or cdef.character_scene == null:
		return
	# Clear any prior character (idempotent on respawn / class swap).
	for child in model_root.get_children():
		child.queue_free()
	var character: Node = cdef.character_scene.instantiate()
	character.name = "Character"
	model_root.add_child(character)
	var skel := _find_node_by_class(character, "Skeleton3D") as Skeleton3D
	anim_player = _find_node_by_class(character, "AnimationPlayer") as AnimationPlayer
	if skel != null:
		weapon_mount = BoneAttachment3D.new()
		weapon_mount.name = "WeaponMount"
		weapon_mount.bone_name = "Weapon.R"
		skel.add_child(weapon_mount)
	for k in cdef.anim_overrides:
		anim_for_state[k] = cdef.anim_overrides[k]
	_apply_anim_loops()


# State names whose clips should loop. Action clips (attack/dodge) and one-shot
# locomotion (jump/fall) play through once. Looping is forced at runtime because
# the gltf imports default loop_mode to LOOP_NONE per clip.
const LOOPING_STATES: Array[StringName] = [&"idle", &"run", &"sprint", &"swim"]

func _apply_anim_loops() -> void:
	if anim_player == null:
		return
	for state in LOOPING_STATES:
		var clip_name: String = String(anim_for_state.get(state, &""))
		if clip_name == "" or not anim_player.has_animation(clip_name):
			continue
		var anim := anim_player.get_animation(clip_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR


func _find_node_by_class(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_class(child, type_name)
		if found != null:
			return found
	return null


## Instantiates the class's weapon scene under weapon_mount. Idempotent (skips
## if a weapon is already mounted, so respawn / re-entry leaves it in place).
## Sets the weapon root's owner to self so the hitbox can read its attacker via
## get_parent().owner (see scripts/combat/hitbox.gd).
func _mount_class_weapon() -> void:
	if weapon_mount == null:
		return
	if weapon_mount.get_child_count() > 0:
		return
	var cdef := ClassRegistry.resolve(class_id)
	if cdef == null or cdef.weapon_scene == null:
		return
	var w: Node = cdef.weapon_scene.instantiate()
	weapon_mount.add_child(w)
	w.owner = self


## Swaps the Attack action-state node's script to the class's attack_state_script.
## ActionSM._ready caches the node by identity, so changing only the script
## (not the node) keeps the cache valid. No-op if the script already matches.
func _apply_attack_state() -> void:
	var cdef := ClassRegistry.resolve(class_id)
	if cdef == null or cdef.attack_state_script == null:
		return
	if actionSM == null:
		return
	var atk: Node = actionSM.get_node_or_null("Attack")
	if atk == null:
		return
	if atk.get_script() != cdef.attack_state_script:
		atk.set_script(cdef.attack_state_script)
		# set_script reinitializes the node's vars to script defaults, wiping
		# the ActionState.player / actionSM refs that ActionSM._ready assigned.
		# Re-bind them here so the new script can reach the player on enter().
		atk.player = self
		atk.actionSM = actionSM


func has_weapon() -> bool:
	return weapon_mount != null and weapon_mount.get_child_count() > 0


func has_block_weapon() -> bool:
	if not has_weapon():
		return false
	var w: Node = weapon_mount.get_child(0)
	return w != null and w.has_method("raise")


const AIM_RANGE := 200.0

## World point the player is currently aiming at — camera origin + forward,
## clipped to the first world/enemy surface hit. Excludes this player's own
## bodies. Used by ranged weapons to derive flight direction from crosshair
## aim rather than the weapon's local axis.
func aim_target() -> Vector3:
	var cam := camera_pivot.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		return global_position + Vector3.FORWARD * AIM_RANGE
	var origin := cam.global_position
	var forward := -cam.global_transform.basis.z.normalized()
	var end := origin + forward * AIM_RANGE
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, end)
	q.collision_mask = CollisionLayers.WORLD | CollisionLayers.HURTBOX
	q.exclude = [self.get_rid(), hurtbox.get_rid()]
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else end


## Awards an item to this player. Runs on the owning peer's authority — the
## server (which owns pickups) calls this via rpc_id so it can credit any player.
@rpc("any_peer", "reliable", "call_local")
func take_pickup(item_id: StringName, count: int) -> void:
	if not is_multiplayer_authority():
		return
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
		# Networked so the attacking enemy (server) hears a guest's parry.
		NetworkManager.broadcast_parried(source)
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
	rotate_y(-delta.x * MOUSE_SENSITIVITY)
	camera_pivot.rotate_x(-delta.y * MOUSE_SENSITIVITY)
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0)
	)


func _physics_process(delta: float) -> void:
	_regen_stamina(delta)
	_update_boat_state()
	if on_boat:
		_ride_boat()
		return  # Boat owns transform; skip movement, action, and move_and_slide.
	movementSM.physics_update(delta)
	actionSM.physics_update(delta)
	move_and_slide()


## Derives boat membership from the (replicated) mounted_peers list of each
## boat. Handles the local mount/dismount collision toggle on transitions.
func _update_boat_state() -> void:
	var my_id := get_multiplayer_authority()
	var found: Boat = null
	for b in get_tree().get_nodes_in_group("boat"):
		if my_id in (b as Boat).mounted_peers:
			found = b as Boat
			break
	var was := on_boat
	_boat = found
	on_boat = found != null
	if on_boat and not was:
		_saved_col_layer = collision_layer
		_saved_col_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
	elif was and not on_boat:
		collision_layer = _saved_col_layer
		collision_mask = _saved_col_mask
		velocity = Vector3.ZERO


## Snap to the assigned deck slot; if driver, forward steering input.
func _ride_boat() -> void:
	if _boat == null or not is_instance_valid(_boat):
		return
	var my_id := get_multiplayer_authority()
	var slot: int = _boat.slot_of(my_id)
	if slot < 0:
		return
	global_position = _boat.deck_slot_transform(slot).origin
	velocity = Vector3.ZERO
	if _boat.is_driver(my_id):
		_boat.submit_drive(Controls.throttle_axis(), Controls.rudder_axis())


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
	# Boats are server-spawned; pass owner_peer_id so each player manages their own boat.
	BoatManager.request_spawn_boat.rpc_id(1, spawn_pos, rotation.y, get_multiplayer_authority())


## Interact: dismount if on a boat, else mount the nearest boat in range.
func _on_interact_pressed() -> void:
	var my_id := get_multiplayer_authority()
	if on_boat and _boat != null:
		_boat.request_dismount.rpc_id(1, my_id)
		return
	var nearest: Boat = null
	var best := Boat.MOUNT_RADIUS
	for b in get_tree().get_nodes_in_group("boat"):
		var boat := b as Boat
		var d := global_position.distance_to(boat.global_position)
		if d <= best:
			best = d
			nearest = boat
	if nearest != null:
		nearest.request_mount.rpc_id(1, my_id)


const SPAWN_RING_RADIUS := 3.0
const SPAWN_SLOTS := 4


func _on_world_loaded() -> void:
	if not is_multiplayer_authority():
		_world_ready = true
		return
	# Grant the class's starting loadout once. Idempotent (per-item count_of
	# guard) so it survives save/load round-trips.
	_apply_starting_inventory()

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
