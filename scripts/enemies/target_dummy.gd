extends StaticBody3D

var hp: float = 50.0

@onready var mesh: MeshInstance3D = $Mesh


## Routes to the multiplayer authority, mirroring Enemy.take_damage.
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
	if hp <= 0.0:
		NetworkManager.broadcast_enemy_killed(&"target_dummy", source)
		_drop_loot()
		queue_free()


@rpc("any_peer", "reliable")
func take_damage_rpc(amount: float, source_path: NodePath) -> void:
	if not is_multiplayer_authority():
		return
	take_damage(amount, get_node_or_null(source_path))


@rpc("authority", "reliable", "call_local")
func _flash() -> void:
	DamageFlash.flash(mesh)


## Server-only — reached on the authority via take_damage.
func _drop_loot() -> void:
	PickupManager.spawn_loot(&"scrap", 1, global_position + Vector3.UP * 0.5)
