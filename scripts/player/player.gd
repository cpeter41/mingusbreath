extends CharacterBody3D

const MOUSE_SENSITIVITY := 0.003
const SWORD_SCENE := preload("res://scenes/weapons/Sword.tscn")

var hp: float      = 100.0
var stamina: float = 100.0
var on_boat: bool  = false
@export var speed: float = 5.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var movementSM: Node = $MovementStateMachine
@onready var actionSM: Node = $ActionStateMachine
@onready var inventory: Inventory = $Inventory
@onready var weapon_mount: Node3D = $WeaponMount


func _ready() -> void:
	add_to_group("player")
	inventory.changed.connect(_on_inventory_changed)
	inventory.add(&"sword", 1)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_inventory_changed() -> void:
	var has_sword := inventory.count_of(&"sword") > 0
	var sword_node := weapon_mount.get_node_or_null("Sword")
	if has_sword and sword_node == null:
		var sword := SWORD_SCENE.instantiate()
		weapon_mount.add_child(sword)
	elif not has_sword and sword_node != null:
		sword_node.queue_free()

func take_pickup(item_id: StringName, count: int) -> void:
	inventory.add(item_id, count)
	EventBus.item_picked_up.emit(item_id, count)


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
	if not on_boat:
		movementSM.physics_update(delta)
	else:
		velocity = Vector3.ZERO
	actionSM.physics_update(delta)
	move_and_slide()
