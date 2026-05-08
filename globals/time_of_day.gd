extends Node

const MINUTES_PER_DAY := 1440.0
const TIME_ACCEL_MULT := 40.0

enum Phase { DAWN, DAY, DUSK, NIGHT }

@export var minutes_per_real_second: float = 1.0

@export var tint_day:   Color = Color(1.0,  1.00, 0.95)
@export var tint_dusk:  Color = Color(0.90, 0.50, 0.30)
@export var tint_night: Color = Color(0.15, 0.18, 0.30)

var game_minutes: float = 0.0
var phase: Phase = Phase.DAY

var _sun: DirectionalLight3D = null
var _env: Environment = null


func _ready() -> void:
	SaveSystem.register(self)


func set_sun(sun: DirectionalLight3D) -> void:
	_sun = sun


func set_world_environment(env: Environment) -> void:
	_env = env


func _process(delta: float) -> void:
	var rate := minutes_per_real_second * (TIME_ACCEL_MULT if Controls.time_accel_held() else 1.0)
	game_minutes += delta * rate
	var m := fmod(game_minutes, MINUTES_PER_DAY)

	var new_phase := _phase_for(m)
	if new_phase != phase:
		phase = new_phase
		EventBus.time_phase_changed.emit(phase)

	if _env != null:
		_env.ambient_light_color = _compute_tint()


func _compute_tint() -> Color:
	if _sun == null or not is_instance_valid(_sun) or not _sun.is_inside_tree():
		return tint_day
	var sun_y: float = _sun.global_transform.basis.z.y
	var day_w   := clampf((sun_y + 0.05) / 0.30, 0.0, 1.0)
	var night_w := clampf((-0.05 - sun_y) / 0.25, 0.0, 1.0)
	var dusk_w  := clampf(1.0 - day_w - night_w, 0.0, 1.0)
	return tint_day * day_w + tint_dusk * dusk_w + tint_night * night_w


func _phase_for(min_in_day: float) -> Phase:
	if min_in_day >= 5 * 60 and min_in_day < 7 * 60:
		return Phase.DAWN
	if min_in_day >= 7 * 60 and min_in_day < 18 * 60:
		return Phase.DAY
	if min_in_day >= 18 * 60 and min_in_day < 20 * 60:
		return Phase.DUSK
	return Phase.NIGHT


func save_data() -> Dictionary:
	return {"game_minutes": game_minutes}


func load_data(d: Dictionary) -> void:
	game_minutes = float(d.get("game_minutes", 8.0 * 60))
	phase = _phase_for(fmod(game_minutes, MINUTES_PER_DAY))
