class_name SkillDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var xp_curve: PackedFloat32Array = [10, 30, 80, 200, 500]  # cumulative XP thresholds per level boundary
@export var per_level_damage_mult: float = 1.0
@export var per_level_stamina_mult: float = 1.0
