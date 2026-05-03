class_name EnemyDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: float = 20.0
@export var damage: float = 5.0
@export var move_speed: float = 3.0
@export var sense_radius: float = 10.0
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 2.0
@export var flee_hp_ratio: float = 0.2
@export var loot_drops: Array[StringName] = []
