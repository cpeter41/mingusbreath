class_name ClassDef
extends Resource

# Player class definition. Schema-only — see docs/planning/class-system/PLAYER_CLASS_FRAMEWORK.md.
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

# Weapon scene instanced under Player.weapon_mount on spawn. Drives the player's
# visible loadout and combat behavior (the scene's root script implements the
# attack-trigger method called by the matching action state).
@export var weapon_scene: PackedScene = null

# Action-state script swapped onto Player/ActionStateMachine/Attack at spawn.
# Picks melee swing / shield bash / ranged fire to match the weapon scene.
@export var attack_state_script: Script = null
