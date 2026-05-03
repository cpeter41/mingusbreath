extends CharacterBody3D

const MOUSE_SENSITIVITY := 0.003
const SWORD_SCENE   := preload("res://scenes/weapons/Sword.tscn")
const SHIELD_SCENE  := preload("res://scenes/weapons/Shield.tscn")
const RESPAWN_POINT := Vector3(0.0, 15.0, 0.0)

var max_hp: float      = 100.0
var max_stamina: float = 150.0
var hp: float          = 100.0
var stamina: float     = 150.0
var on_boat: bool      = false
var is_blocking: bool  = false
var is_parrying: bool  = false

@export var speed: float = 5.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _stamina_regen_timer: float = 999.0

@onready var camera_pivot: Node3D  = $CameraPivot
@onready var movementSM: Node      = $MovementStateMachine
@onready var actionSM: Node        = $ActionStateMachine
@onready var inventory: Inventory  = $Inventory
@onready var weapon_mount: Node3D  = $WeaponMount
@onready var shield_mount: Node3D  = $ShieldMount
@onready var hurtbox: Area3D       = $Hurtbox


func _ready() -> void:
	add_to_group("player")
	inventory.changed.connect(_on_inventory_changed)
	inventory.add(&"sword", 1)
	inventory.add(&"shield", 1)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	EventBus.player_hp_changed.emit.call_deferred(hp, max_hp)
	EventBus.player_stamina_changed.emit.call_deferred(stamina, max_stamina)


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
	get_tree().create_timer(0.6).timeout.connect(respawn)


func respawn() -> void:
	global_position = RESPAWN_POINT
	hp = max_hp
	stamina = max_stamina
	_stamina_regen_timer = 999.0
	EventBus.player_hp_changed.emit(hp, max_hp)
	EventBus.player_stamina_changed.emit(stamina, max_stamina)
	EventBus.player_respawned.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		)
		return

	if not on_boat and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(20.0)
		)

	if not on_boat:
		movementSM.handle_input(event)
	actionSM.handle_input(event)


func _physics_process(delta: float) -> void:
	_regen_stamina(delta)
	if not on_boat:
		movementSM.physics_update(delta)
	else:
		velocity = Vector3.ZERO
	actionSM.physics_update(delta)
	move_and_slide()


func _regen_stamina(delta: float) -> void:
	_stamina_regen_timer += delta
	if _stamina_regen_timer > 0.5 and stamina < max_stamina:
		stamina = minf(max_stamina, stamina + 15.0 * delta)
		EventBus.player_stamina_changed.emit(stamina, max_stamina)
