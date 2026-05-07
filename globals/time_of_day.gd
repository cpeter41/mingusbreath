extends Node

const MINUTES_PER_DAY := 1440.0
const TIME_ACCEL_MULT := 40.0

enum Phase { DAWN, DAY, DUSK, NIGHT }

@export var minutes_per_real_second: float = 1.0

@export var tint_dawn:  Color = Color(1.0,  0.70, 0.40)
@export var tint_day:   Color = Color(1.0,  1.00, 0.95)
@export var tint_dusk:  Color = Color(0.90, 0.50, 0.30)
@export var tint_night: Color = Color(0.15, 0.18, 0.30)

## Above this elevation (in basis.z.y units, 0 = horizon, 1 = zenith)
## the celestial body shines at full strength. Below 0 it's dark. Linear fade between.
const HORIZON_FADE := 0.1

var game_minutes: float = 0.0
var phase: Phase = Phase.DAY

var _sun: DirectionalLight3D = null
var _moon: DirectionalLight3D = null
var _env: Environment = null
var _sun_max_energy: float = 1.0
var _moon_max_energy: float = 0.15


func _ready() -> void:
	SaveSystem.register(self)


func set_sun(sun: DirectionalLight3D) -> void:
	_sun = sun
	_sun_max_energy = sun.light_energy


func set_moon(moon: DirectionalLight3D) -> void:
	_moon = moon
	_moon_max_energy = moon.light_energy


func set_world_environment(env: Environment) -> void:
	_env = env


func _process(delta: float) -> void:
	var time_rate := minutes_per_real_second * (TIME_ACCEL_MULT if Controls.time_accel_held() else 1.0)
	game_minutes += delta * time_rate
	var m := fmod(game_minutes, MINUTES_PER_DAY)

	var new_phase := _phase_for(m)
	if new_phase != phase:
		phase = new_phase
		EventBus.time_phase_changed.emit(phase)

	if _sun != null:
		_sun.rotation.x = deg_to_rad(90.0 * cos(TAU * m / MINUTES_PER_DAY))
		_sun.light_energy = _sun_max_energy * _horizon_factor(_sun)
	if _moon != null:
		_moon.rotation.x = _sun.rotation.x + PI
		_moon.light_energy = _moon_max_energy * _horizon_factor(_moon)
	if _env != null:
		_env.ambient_light_color = _compute_tint(m)


## 1.0 when the body is above HORIZON_FADE elevation, 0.0 at/below horizon, linear in between.
func _horizon_factor(light: DirectionalLight3D) -> float:
	var elevation: float = light.global_transform.basis.z.y
	return clampf(elevation / HORIZON_FADE, 0.0, 1.0)


## Ambient tint follows sun elevation (drives indirect light to match sky shader).
func _compute_tint(_m: float) -> Color:
	if _sun == null:
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
