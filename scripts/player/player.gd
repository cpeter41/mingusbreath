extends CharacterBody3D

const MOUSE_SENSITIVITY := 0.003
const SWORD_SCENE   := preload("res://scenes/weapons/Sword.tscn")
const SHIELD_SCENE  := preload("res://scenes/weapons/Shield.tscn")
const BOAT_SCENE    := preload("res://scenes/ships/Boat.tscn")
const RESPAWN_FALLBACK_Y := 15.0
const BOAT_SPAWN_DIST := 8.0

@export var max_hp: float      = 100.0
@export var max_stamina: float = 150.0
var hp: float          = 0.0
var stamina: float     = 0.0
var on_boat: bool      = false
var is_blocking: bool  = false
var is_parrying: bool  = false

@export var speed: float = 5.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _stamina_regen_timer: float = 999.0
var _has_pending_pos: bool = false
var _pending_pos: Vector3 = Vector3.ZERO
var _pending_rot_y: float = 0.0
var _world_ready: bool = false  # true after _on_world_loaded places the player
var _save_pos: Vector3 = Vector3.ZERO
var _save_rot_y: float = 0.0

@onready var camera_pivot: Node3D  = $CameraPivot
@onready var movementSM: Node      = $MovementStateMachine
@onready var actionSM: Node        = $ActionStateMachine
@onready var inventory: Inventory  = $Inventory
@onready var weapon_mount: Node3D  = $WeaponMount
@onready var shield_mount: Node3D  = $ShieldMount
@onready var hurtbox: Area3D       = $Hurtbox


func _ready() -> void:
	hp = max_hp
	stamina = max_stamina
	add_to_group("player")
	inventory.changed.connect(_on_inventory_changed)
	Controls.capture_mouse()
	Controls.pause_pressed.connect(_on_pause_pressed)
	Controls.reset_pressed.connect(_on_reset_pressed)
	Controls.spawn_boat_pressed.connect(_on_spawn_boat_pressed)
	Controls.mouse_look.connect(_on_mouse_look)
	EventBus.player_hp_changed.emit.call_deferred(hp, max_hp)
	EventBus.player_stamina_changed.emit.call_deferred(stamina, max_stamina)
	SaveSystem.register(self)
	EventBus.world_loaded.connect(_on_world_loaded, CONNECT_ONE_SHOT)


func _on_inventory_changed() -> void:
	var has_sword := inventory.count_of(&"sword") > 0
	var sword_node := weapon_mount.get_node_or_null("Sword")
	if has_sword and sword_node == null:
		var sword := SWORD_SCENE.instantiate()
		weapon_mount.add_child(sword)
	elif not has_sword and sword_node != null:
		sword_node.queue_free()

	var shld := inventory.count_of(&"shield") > 0
	var shield_node := shield_mount.get_node_or_null("Shield")
	if shld and shield_node == null:
		var s := SHIELD_SCENE.instantiate()
		shield_mount.add_child(s)
	elif not shld and shield_node != null:
		shield_node.queue_free()
		if is_blocking:
			actionSM.transition_to("idle")


func has_shield() -> bool:
	return inventory.count_of(&"shield") > 0


func take_pickup(item_id: StringName, count: int) -> void:
	inventory.add(item_id, count)
	EventBus.item_picked_up.emit(item_id, count)


func take_damage(amount: float, source = null) -> void:
	if is_parrying:
		EventBus.player_parried.emit(source)
		return
	if is_blocking:
		var cost := amount * 0.5
		if consume_stamina(cost):
			amount *= 0.2
		# stamina too low — block fails, full damage applies
	hp = maxf(0.0, hp - amount)
	EventBus.player_hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		die()


func consume_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	_stamina_regen_timer = 0.0
	EventBus.player_stamina_changed.emit(stamina, max_stamina)
	return true


func die() -> void:
	EventBus.player_died.emit()
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(self):
		return
	respawn()


func respawn() -> void:
	global_position = _mainland_spawn_point()
	hp = max_hp
	stamina = max_stamina
	_stamina_regen_timer = 999.0
	EventBus.player_hp_changed.emit(hp, max_hp)
	EventBus.player_stamina_changed.emit(stamina, max_stamina)
	EventBus.player_respawned.emit()


func _on_pause_pressed() -> void:
	Controls.toggle_mouse_capture()


func _on_reset_pressed() -> void:
	SaveSystem.disable_save()
	SaveSystem.delete_save()
	get_tree().paused = false
	Controls.capture_mouse()
	get_tree().reload_current_scene()


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


func _exit_tree() -> void:
	if _world_ready:
		_save_pos = global_position
		_save_rot_y = rotation.y


func save_data() -> Dictionary:
	if not _world_ready:
		return {}
	return {"position": V3Codec.encode(_save_pos), "rotation_y": _save_rot_y}


func load_data(d: Dictionary) -> void:
	if d.has("position"):
		_pending_pos = V3Codec.decode(d["position"])
		_pending_rot_y = float(d.get("rotation_y", 0.0))
		_has_pending_pos = true


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


func _on_world_loaded() -> void:
	# Grant starter loadout once. Idempotent so it survives save/load round-trips.
	if inventory.count_of(&"sword") == 0:
		inventory.add(&"sword", 1)
	if inventory.count_of(&"shield") == 0:
		inventory.add(&"shield", 1)

	if _has_pending_pos:
		global_position = _pending_pos
		rotation.y = _pending_rot_y
	else:
		global_position = _mainland_spawn_point()
	velocity = Vector3.ZERO
	_world_ready = true


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
