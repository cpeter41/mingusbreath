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

# Character model scene (a gltf from assets/characters/...) instanced under
# Player/Model at spawn. Drives the visible body, skeleton, AnimationPlayer,
# and the Weapon.R bone the weapon mount attaches to.
@export var character_scene: PackedScene = null

# Per-class animation-clip overrides. Keys = movement/action state names
# (idle/run/sprint/jump/fall/swim/attack/dodge); values = clip names in the
# character's AnimationPlayer. Merged into Player.anim_for_state on spawn so
# only the differing clips need to be listed (typically just "attack" since
# each class's character has its own attack-clip name).
@export var anim_overrides: Dictionary = {}
