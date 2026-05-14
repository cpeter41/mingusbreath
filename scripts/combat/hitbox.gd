class_name Hitbox
extends Area3D

@export var damage: float = 10.0
@export var weapon_id: StringName = &"sword"
@export var skill_id: StringName = &"swords"

func _ready() -> void:
	monitoring = false      # enabled only during active swing window
	collision_layer = CollisionLayers.HITBOX
	collision_mask  = CollisionLayers.HURTBOX
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area3D) -> void:
	if not area is Hurtbox:
		return
	var target   := area.owner
	var attacker := get_parent().owner  # Sword.owner = Player (set when instanced in Player.tscn)
	# Only the attacker's authority peer applies damage. Without this, future
	# inventory replication would make the hitbox visible on all peers and each
	# would call take_damage on the same hit.
	if attacker != null and attacker.has_method("is_multiplayer_authority") and not attacker.is_multiplayer_authority():
		return
	# Don't self-hit (player's own hitbox touching their own hurtbox).
	if target == attacker:
		return
	var amount   := CombatResolver.resolve(attacker, target, weapon_id, damage, skill_id)
	EventBus.damage_dealt.emit(attacker, target, weapon_id, skill_id, amount)
	SkillManager.add_xp(skill_id, amount * 0.1)
	if target.has_method("take_damage"):
		target.take_damage(amount, attacker)
