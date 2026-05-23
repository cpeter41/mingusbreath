class_name ClassDef
extends Resource

# Player class definition. Schema-only — see docs/planning/PLAYER_CLASS_FRAMEWORK.md.
# Add a new per-class parameter = one @export here + one line in Player._apply_class().

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null

# Stats applied to the Player on spawn.
@export var max_hp: float = 100.0
@export var max_stamina: float = 150.0
@export var move_speed: float = 5.0

# Granted once, idempotently, at world load (see Player._apply_starting_inventory).
# Typed as Array[Resource] (not Array[ClassLoadoutEntry]) so this schema parses
# without depending on Godot's class_name global cache being current — the
# entries are ClassLoadoutEntry instances at runtime (bound by their .tres
# script reference). Mirrors InventoryRegistry/ItemDef typing style.
@export var starting_inventory: Array[Resource] = []

# Item id (from data/items/) of the class's primary weapon. Informational in
# this phase; kept separate from starting_inventory so future logic (HUD weapon
# glyph, default-equipped slot, model/anim selection) can read it directly.
@export var primary_weapon: StringName = &""
