## Single source of truth for all player input.
## Other code subscribes to signals (discrete press events) or calls helper
## queries (continuous holds, mouse capture). No file outside this one should
## touch `Input.*` or raw `KEY_*` constants.
extends Node

# ── Action names ─────────────────────────────────────────────────
const MOVE_FORWARD   := &"move_forward"
const MOVE_BACK      := &"move_back"
const MOVE_LEFT      := &"move_left"
const MOVE_RIGHT     := &"move_right"
const JUMP           := &"jump"
const SPRINT         := &"sprint"
const DODGE          := &"dodge"
const ATTACK_LIGHT   := &"attack_light"
const ATTACK_HEAVY   := &"attack_heavy"
const BLOCK          := &"block"
const INTERACT       := &"interact"
const INVENTORY      := &"inventory"
const PAUSE          := &"pause"
const SPAWN_BOAT     := &"spawn_boat"
const RESET_SAVE     := &"reset_save"
const TIME_ACCEL     := &"time_accel"
const THROTTLE_UP    := &"throttle_up"
const THROTTLE_DOWN  := &"throttle_down"
const RUDDER_LEFT    := &"rudder_left"
const RUDDER_RIGHT   := &"rudder_right"
const FIRE_CANNON    := &"fire_cannon"

# ── Discrete-event signals ───────────────────────────────────────
signal pause_pressed
signal reset_pressed
signal spawn_boat_pressed
signal interact_pressed
signal inventory_toggled
signal mouse_look(delta: Vector2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PAUSE):
		pause_pressed.emit()
		return
	if event.is_action_pressed(RESET_SAVE):
		reset_pressed.emit()
		return
	if event.is_action_pressed(SPAWN_BOAT):
		spawn_boat_pressed.emit()
		return
	if event.is_action_pressed(INTERACT):
		interact_pressed.emit()
		return
	if event.is_action_pressed(INVENTORY):
		inventory_toggled.emit()
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		mouse_look.emit((event as InputEventMouseMotion).relative)


# ── Continuous-hold queries ──────────────────────────────────────
func move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_FORWARD, MOVE_BACK)


func sprint_held() -> bool:
	return Input.is_action_pressed(SPRINT)


func block_held() -> bool:
	return Input.is_action_pressed(BLOCK)


func attack_light_held() -> bool:
	return Input.is_action_pressed(ATTACK_LIGHT)


func time_accel_held() -> bool:
	return Input.is_action_pressed(TIME_ACCEL)


func jump_just_pressed() -> bool:
	return Input.is_action_just_pressed(JUMP)


func dodge_just_pressed() -> bool:
	return Input.is_action_just_pressed(DODGE)


func throttle_axis() -> float:
	return Input.get_action_strength(THROTTLE_UP) - Input.get_action_strength(THROTTLE_DOWN)


func rudder_axis() -> float:
	return Input.get_action_strength(RUDDER_LEFT) - Input.get_action_strength(RUDDER_RIGHT)


# ── Mouse-mode helpers ───────────────────────────────────────────
func is_mouse_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func toggle_mouse_capture() -> void:
	if is_mouse_captured():
		release_mouse()
	else:
		capture_mouse()
