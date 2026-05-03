extends Node

enum Phase { DAWN, DAY, DUSK, NIGHT }

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


func _process(_delta: float) -> void:
	pass


func save_data() -> Dictionary:
	return {"game_minutes": game_minutes}


func load_data(d: Dictionary) -> void:
	game_minutes = float(d.get("game_minutes", 8.0 * 60))
	phase = _phase_for(fmod(game_minutes, 1440.0))


func _phase_for(min_in_day: float) -> Phase:
	if min_in_day >= 5 * 60 and min_in_day < 7 * 60:
		return Phase.DAWN
	if min_in_day < 18 * 60:
		return Phase.DAY
	if min_in_day < 20 * 60:
		return Phase.DUSK
	return Phase.NIGHT
