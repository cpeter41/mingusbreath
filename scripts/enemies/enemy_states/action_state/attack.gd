extends EnemyActionState

const TELEGRAPH_TIME := 0.4
const STRIKE_TIME    := 0.15

enum Phase { TELEGRAPH, STRIKE, COOLDOWN }

var _phase: Phase = Phase.TELEGRAPH
var _timer: float  = 0.0
var _hit_this_strike: bool = false
var _mesh_tween: Tween


func enter() -> void:
	_phase = Phase.TELEGRAPH
	_timer = TELEGRAPH_TIME
	_hit_this_strike = false
	enemy.attack_hitbox.monitoring = false
	enemy.attack_hitbox.collision_mask = 4   # hurtbox layer
	if not enemy.attack_hitbox.area_entered.is_connected(_on_hitbox_entered):
		enemy.attack_hitbox.area_entered.connect(_on_hitbox_entered)
	if not EventBus.player_parried.is_connected(_on_player_parried):
		EventBus.player_parried.connect(_on_player_parried)
	_face_player()
	_set_telegraph_visual(true)
	_lean_mesh(-20.0, TELEGRAPH_TIME * 0.9)


func physics_update(delta: float) -> void:
	_timer -= delta
	match _phase:
		Phase.TELEGRAPH:
			if _timer <= 0.0:
				_set_telegraph_visual(false)
				_phase = Phase.STRIKE
				_timer = STRIKE_TIME
				_hit_this_strike = false
				enemy.attack_hitbox.monitoring = true
				_lean_mesh(-35.0, 0.06)
		Phase.STRIKE:
			if _timer <= 0.0:
				enemy.attack_hitbox.monitoring = false
				_phase = Phase.COOLDOWN
				_timer = enemy.def.attack_cooldown
				_lean_mesh(0.0, 0.35)
		Phase.COOLDOWN:
			if _timer <= 0.0:
				actionSM.transition_to("idle")


func exit() -> void:
	enemy.attack_hitbox.set_deferred("monitoring", false)
	_set_telegraph_visual(false)
	if _mesh_tween:
		_mesh_tween.kill()
	var mesh := enemy.get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.rotation.x = 0.0
	if enemy.attack_hitbox.area_entered.is_connected(_on_hitbox_entered):
		enemy.attack_hitbox.area_entered.disconnect(_on_hitbox_entered)
	if EventBus.player_parried.is_connected(_on_player_parried):
		EventBus.player_parried.disconnect(_on_player_parried)


func _on_hitbox_entered(area: Area3D) -> void:
	if _hit_this_strike or _phase != Phase.STRIKE:
		return
	if not (area is Hurtbox):
		return
	var target := area.owner
	if not target.has_method("take_damage"):
		return
	_hit_this_strike = true
	var amount := CombatResolver.resolve(enemy, target, &"", enemy.def.damage)
	EventBus.damage_dealt.emit(enemy, target, &"", &"", amount)
	target.take_damage(amount, enemy)


func _on_player_parried(source: Node) -> void:
	if source != enemy:
		return
	enemy.attack_hitbox.set_deferred("monitoring", false)
	_set_telegraph_visual(false)
	actionSM.transition_to("stagger")


func _face_player() -> void:
	var player := enemy.get_player()
	if not player:
		return
	var flat_target := Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z)
	if flat_target.distance_squared_to(enemy.global_position) > 0.001:
		enemy.look_at(flat_target, Vector3.UP)


func _lean_mesh(target_deg: float, duration: float) -> void:
	var mesh := enemy.get_node_or_null("Mesh") as MeshInstance3D
	if not mesh:
		return
	if _mesh_tween:
		_mesh_tween.kill()
	_mesh_tween = enemy.create_tween()
	_mesh_tween.tween_property(mesh, "rotation:x", deg_to_rad(target_deg), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _set_telegraph_visual(on: bool) -> void:
	var mesh := enemy.get_node_or_null("Mesh") as MeshInstance3D
	if not mesh:
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
