class_name IslandDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
## Far tier — terrain mesh + collider. Always loaded once player enters world.
@export var scene: PackedScene = null
## Mid tier — foliage. Loaded when player approaches footprint.
@export var mid_scene: PackedScene = null
## Near tier — items, enemies, DeltaRoot. Loaded only when player is on/near the island.
@export var near_scene: PackedScene = null
@export var biome: BiomeDef = null
@export var footprint_radius: float = 80.0
@export var placement_weight: float = 1.0
