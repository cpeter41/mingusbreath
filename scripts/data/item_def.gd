class_name ItemDef
extends Resource

enum ItemType { GENERIC, MATERIAL, WEAPON, TOOL, CONSUMABLE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
@export var max_stack: int = 99
@export var item_type: ItemType = ItemType.GENERIC
@export var weapon_skill_id: StringName = &""
