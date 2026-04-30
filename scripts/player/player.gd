extends CharacterBody3D

const MOUSE_SENSITIVITY := 0.003

var hp: float      = 100.0
var stamina: float = 100.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var state_machine: Node  = $StateMachine


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		)
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(20.0)
		)

	state_machine.handle_input(event)


func _physics_process(delta: float) -> void:
	state_machine.physics_update(delta)
	move_and_slide()
