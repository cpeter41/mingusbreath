class_name Enemy
extends CharacterBody3D

@export var def: EnemyDef

var hp: float = 0.0
var spawn_anchor: Vector3 = Vector3.ZERO

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var movementSM: EnemyMovementSM = $EnemyMovementSM
@onready var actionSM: EnemyActionSM = $EnemyActionSM
@onready var hurtbox: Area3D = $Hurtbox
@onready var attack_hitbox: Area3D = $AttackHitbox
@onready var _mesh: MeshInstance3D = $Mesh

var _hit_mat: StandardMaterial3D


func _ready() -> void:
	assert(def != null, "Enemy requires an EnemyDef resource")
	hp = def.max_hp
	spawn_anchor = global_position
	_hit_mat = StandardMaterial3D.new()
	_hit_mat.albedo_color = Color.RED
	attack_hitbox.monitoring = false
	_ensure_collision_shapes()


func _ensure_collision_shapes() -> void:
	var body_col := $CollisionShape3D as CollisionShape3D
	if body_col and body_col.shape == null:
		var cap := CapsuleShape3D.new()
		cap.height = 1.8
		cap.radius = 0.4
		body_col.shape = cap

	var hurtbox_col := $Hurtbox/HurtboxShape as CollisionShape3D
	if hurtbox_col and hurtbox_col.shape == null:
		var cap := CapsuleShape3D.new()
		cap.height = 1.6
		cap.radius = 0.4
		hurtbox_col.shape = cap

	var atk_col := $AttackHitbox/AttackHitboxShape as CollisionShape3D
	if atk_col and atk_col.shape == null:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.6
		atk_col.shape = sphere


func _physics_process(delta: float) -> void:
	movementSM.physics_update(delta)
	actionSM.physics_update(delta)
	move_and_slide()


func take_damage(amount: float, source: Node = null) -> void:
	hp -= amount
	_flash_red()
	if hp <= def.flee_hp_ratio * def.max_hp and hp > 0.0:
		movementSM.transition_to("flee")
	if hp <= 0.0:
		_die(source)


func _die(source: Node) -> void:
	EventBus.enemy_killed.emit(def.id, source)
	_drop_loot()
	queue_free()


func _drop_loot() -> void:
	for item_id in def.loot_drops:
		var pickup := ItemPickup.new()
		pickup.item_id = item_id
		pickup.count = 1
		get_parent().add_child(pickup)
		pickup.spring(global_position + Vector3.UP * 0.5)


func _flash_red() -> void:
	_mesh.material_override = _hit_mat
	var t := create_tween()
	t.tween_interval(0.15)
	t.tween_callback(func():
		if is_instance_valid(self):
			_mesh.material_override = null
	)


func get_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
