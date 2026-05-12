extends Node

const WATER_BASE_Y := -0.15
const GRAVITY      := 9.81
# 2^14 — keeps shader-side float32 phase precision sub-millirad; see plan for wrap-discontinuity notes.
const TIME_MOD     := 16384.0
const STEEPNESS    := 0.30
const WAVES: Array[Vector4] = [
	Vector4( 1.000,  0.000, 0.30, 30.0),  # primary swell
	Vector4( 0.866,  0.500, 0.18, 18.0),  # secondary swell ~30° off
	Vector4( 0.500,  0.866, 0.10, 10.0),  # medium chop ~60° off
	Vector4(-0.500,  0.866, 0.07,  6.0),  # short chop ~120° off
]

var global_roughness: float = 1.0
var time: float = 0.0

var _material: ShaderMaterial = null


func _process(delta: float) -> void:
	time = fmod(time + delta, TIME_MOD)
	if _material != null:
		_material.set_shader_parameter("wave_time", time)
		_material.set_shader_parameter("wave_roughness", global_roughness)


func set_water_material(mat: ShaderMaterial) -> void:
	_material = mat
	if _material == null:
		return
	_material.set_shader_parameter("waves", WAVES)
	_material.set_shader_parameter("gravity", GRAVITY)
	_material.set_shader_parameter("steepness", STEEPNESS)
	_material.set_shader_parameter("time_mod", TIME_MOD)


func roughness_at(_x: float, _z: float, _t: float) -> float:
	return global_roughness


func get_height(x: float, z: float, t: float) -> float:
	# Physics ignores Gerstner horizontal displacement — evaluates vertical contribution
	# directly at query (x, z). Error bounded by ~0.20 m; see plan for rationale.
	var sum := 0.0
	for w in WAVES:
		var k     := TAU / w.w
		var omega := sqrt(GRAVITY * k)
		var phase := k * (w.x * x + w.y * z) - omega * t
		sum += w.z * sin(phase)
	return WATER_BASE_Y + roughness_at(x, z, t) * sum
