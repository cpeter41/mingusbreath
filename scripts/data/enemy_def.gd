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

# Character model scene (a gltf from assets/characters/...) instanced under the
# enemy's Model node at spawn. Drives the visible body, skeleton, and
# AnimationPlayer the enemy FSM plays clips on.
@export var character_scene: PackedScene = null

# Per-enemy animation-clip overrides. Keys = FSM state names
# (idle/patrol/chase/attack/flee); values = clip names in the character's
# AnimationPlayer. Merged into the enemy's anim map on spawn so only differing
# clips need to be listed.
@export var anim_overrides: Dictionary = {}
