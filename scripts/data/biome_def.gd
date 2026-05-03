class_name BiomeDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var terrain_albedo: Color = Color(0.5, 0.5, 0.5)
@export var terrain_roughness: float = 0.85
@export var foliage_density: float = 1.0  # reserved — Phase 6+
@export var fog_tint: Color = Color(1, 1, 1, 0)  # alpha 0 = no override
@export var ambient_tint_day: Color = Color(1, 1, 1, 1)
@export var ambient_tint_night: Color = Color(0.4, 0.4, 0.55, 1)
@export var day_spawn_table: Array[StringName] = []  # reserved — Phase 6+
@export var night_spawn_table: Array[StringName] = []  # reserved — Phase 6+
@export var music_stem: AudioStream = null  # reserved — Phase 7+
