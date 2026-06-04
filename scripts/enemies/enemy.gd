class_name Enemy
extends CharacterBody3D

@export var def: EnemyDef

var hp: float = 0.0
var spawn_anchor: Vector3 = Vector3.ZERO

## Replicated. The attack state sets it on the server; the setter applies the
## red telegraph tint on every peer when the change replicates in.
var telegraphing: bool = false:
	set(v):
		telegraphing = v
		_apply_telegraph_visual(v)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var movementSM: EnemyMovementSM = $EnemyMovementSM
@onready var actionSM: EnemyActionSM = $EnemyActionSM
@onready var hurtbox: Area3D = $Hurtbox
@onready var attack_hitbox: Area3D = $AttackHitbox
@onready var mesh: MeshInstance3D = $Mesh

# Populated by _apply_character_model() at spawn — lives inside the def's
# character_scene (varies per enemy) so can't be an @onready path.
var anim_player: AnimationPlayer = null


func _ready() -> void:
	assert(def != null, "Enemy requires an EnemyDef resource")
	hp = def.max_hp
	spawn_anchor = global_position
	attack_hitbox.monitoring = false
	_ensure_collision_shapes()
	_apply_character_model()

	# Server-authoritative: only the host runs AI + physics + the hitbox. Clients
	# freeze and display the replicated transform / hp / telegraph state.
	if not multiplayer.is_server():
		set_physics_process(false)
		attack_hitbox.monitoring = false


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


## Public damage entry. Routes to the multiplayer authority (the host, since
## enemies spawn server-side). Mirrors Player.take_damage.
func take_damage(amount: float, source: Node = null) -> void:
	if not is_multiplayer_authority():
		var sp: NodePath = source.get_path() if source is Node else NodePath()
		rpc_id(get_multiplayer_authority(), "take_damage_rpc", amount, sp)
		return
	hp -= amount
	if multiplayer.multiplayer_peer == null:
		DamageFlash.flash(mesh)
	else:
		_flash.rpc()
	if hp <= def.flee_hp_ratio * def.max_hp and hp > 0.0:
		movementSM.transition_to("flee")
	if hp <= 0.0:
		_die(source)


@rpc("any_peer", "reliable")
func take_damage_rpc(amount: float, source_path: NodePath) -> void:
	if not is_multiplayer_authority():
		return
	take_damage(amount, get_node_or_null(source_path))


@rpc("authority", "reliable", "call_local")
func _flash() -> void:
	DamageFlash.flash(mesh)


## Server-only — reached on the authority via take_damage.
func _die(source: Node) -> void:
	NetworkManager.broadcast_enemy_killed(def.id, source)
	_drop_loot()
	queue_free()


## Server-only. Drops are transient by design — husks roam open ocean, no
## DeltaRoot to persist into.
func _drop_loot() -> void:
	for item_id in def.loot_drops:
		PickupManager.spawn_loot(item_id, 1, global_position + Vector3.UP * 0.5)


## Instantiates the def's character_scene as a child of the placeholder $Mesh
## node. $Mesh keeps its transform (action states tilt it for lean/telegraph)
## but its capsule visual is cleared so only the rig renders. Locates the
## AnimationPlayer inside the rig for the FSM to drive.
func _apply_character_model() -> void:
	if def == null or def.character_scene == null:
		return
	if mesh == null:
		return
	# Clear placeholder capsule but keep node — attack lean tilts mesh.rotation.x.
	mesh.mesh = null
	# Idempotent on respawn / def swap.
	for child in mesh.get_children():
		if child.name == "Character":
			child.queue_free()
	var character: Node = def.character_scene.instantiate()
	character.name = "Character"
	mesh.add_child(character)
	# Rigged glTF chars import facing +Z; Godot forward is -Z. Player.tscn bakes
	# this fix on its $Model node; we apply it in code since $Mesh has no preset.
	if character is Node3D:
		(character as Node3D).rotate_y(PI)
	anim_player = _find_node_by_class(character, "AnimationPlayer") as AnimationPlayer


func _find_node_by_class(root: Node, klass: String) -> Node:
	if root.is_class(klass):
		return root
	for child in root.get_children():
		var hit := _find_node_by_class(child, klass)
		if hit != null:
			return hit
	return null


func _apply_telegraph_visual(on: bool) -> void:
	if mesh == null:
		return
	if on:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.0, 0.0)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat
	else:
		mesh.material_override = null


## Nearest of all connected players. Searches /World/Players (the MP container);
## falls back to the "player" group for the offline dev sandbox (test_island,
## which has no Players container).
func get_player() -> Node3D:
	var scene := get_tree().current_scene
	if scene != null:
		var players := scene.get_node_or_null("Players")
		if players != null:
			var best: Node3D = null
			var best_d := INF
			for c in players.get_children():
				var d := global_position.distance_to((c as Node3D).global_position)
				if d < best_d:
					best_d = d
					best = c
			return best
	var grp := get_tree().get_nodes_in_group("player")
	return grp[0] as Node3D if not grp.is_empty() else null
