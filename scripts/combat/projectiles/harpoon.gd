extends Area3D

# Server-authoritative projectile. Host runs physics and applies damage; clients
# see a replicated ghost driven by position/rotation sync. Simpler than shooter-
# authority because MultiplayerSpawner does not replicate set_multiplayer_authority
# calls (see Player._enter_tree comment for the same reason).

const SPEED := 40.0
const LIFETIME := 3.0
const DAMAGE := 25.0
const WEAPON_ID := &"harpoon"
const SKILL_ID := &"swords"   # no archery skill yet — reuse swords for now

# Spawn-replicated (set on host before add_child).
var velocity: Vector3 = Vector3.ZERO
var shooter_path: NodePath = NodePath()

var _life: float = LIFETIME
var _hit: bool = false


func _ready() -> void:
	collision_layer = CollisionLayers.HITBOX
	collision_mask = CollisionLayers.HURTBOX
	monitoring = true
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	global_position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if _hit or not multiplayer.is_server() or not area is Hurtbox:
		return
	var target := area.owner
	var shooter: Node = get_node_or_null(shooter_path)
	if target == shooter:
		return
	_hit = true
	var amount := CombatResolver.resolve(shooter, target, WEAPON_ID, DAMAGE, SKILL_ID)
	NetworkManager.broadcast_damage(shooter, target, WEAPON_ID, SKILL_ID, amount)
	SkillManager.add_xp(SKILL_ID, amount * 0.1)
	if target != null and target.has_method("take_damage"):
		target.take_damage(amount, shooter)
	queue_free()
