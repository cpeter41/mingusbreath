extends Area3D

# Server-authoritative projectile. Host runs physics and applies damage; clients
# see a replicated ghost driven by position/rotation sync. Simpler than shooter-
# authority because MultiplayerSpawner does not replicate set_multiplayer_authority
# calls (see Player._enter_tree comment for the same reason).
#
# ── Collision matrix ─────────────────────────────────────────────────────────
# Layers we care about now (scripts/shared/collision_layers.gd):
#   WORLD   — terrain, players, enemies (StaticBody3D / CharacterBody3D)
#   HURTBOX — passive damage receivers (Area3D on enemies/players)
#   HITBOX  — active swing volumes (the harpoon itself sits here)
#
# Detection split:
#   area_entered → HURTBOX hits (damage flow).
#   body_entered → WORLD hits   (terrain stop; no damage).
#
# To make harpoons collide with a NEW layer in the future:
#   1. Add the bit to collision_mask below (HURTBOX | WORLD | NEW_LAYER).
#   2. If the new collider is an Area3D, extend _on_area_entered.
#      If it's a PhysicsBody3D (Static/Character/Rigid), extend _on_body_entered.
#   3. Decide whether the hit deals damage or just stops the projectile —
#      _on_body_entered's "no damage, just despawn" branch is the template.

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
	collision_mask = CollisionLayers.HURTBOX | CollisionLayers.WORLD
	monitoring = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


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
	NetworkManager.broadcast_projectile_hit_debug(global_position)
	SkillManager.add_xp(SKILL_ID, amount * 0.1)
	if target != null and target.has_method("take_damage"):
		target.take_damage(amount, shooter)
	queue_free()


## Terrain (and any other WORLD-layer body) stops the harpoon without damage.
## Player bodies also live on WORLD; skip the shooter so a self-spawned harpoon
## doesn't insta-despawn on its own body the frame it leaves the bow.
func _on_body_entered(body: Node) -> void:
	if _hit or not multiplayer.is_server():
		return
	var shooter: Node = get_node_or_null(shooter_path)
	if body == shooter:
		return
	_hit = true
	NetworkManager.broadcast_projectile_hit_debug(global_position)
	queue_free()
