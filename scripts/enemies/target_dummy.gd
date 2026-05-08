extends StaticBody3D

var hp: float = 50.0

@onready var _mesh: MeshInstance3D = $Mesh

var _hit_mat: StandardMaterial3D


func _ready() -> void:
	_hit_mat = StandardMaterial3D.new()
	_hit_mat.albedo_color = Color.RED


func take_damage(amount: float, source: Node = null) -> void:
	hp -= amount
	_flash_red()
	if hp <= 0.0:
		EventBus.enemy_killed.emit(&"target_dummy", source)
		_drop_loot()
		queue_free()

func _drop_loot() -> void:
	var pickup := ItemPickup.new()
	pickup.item_id = &"scrap"
	pickup.count = 1

	var placement: IslandPlacement = WorldStream.get_placement_enclosing(global_position)
	if placement != null:
		var delta_root: Node3D = WorldStream.get_delta_root(placement.runtime_id)
		if delta_root != null:
			# Phase 5 placements use rotation_y = 0, so plain subtraction == local position.
			var local_pos := global_position - placement.position
			var payload := {
				"item_id": &"scrap",
				"count": 1,
				"local_position": V3Codec.encode(local_pos),
			}
			WorldStream.get_delta_store().add_delta(placement.runtime_id, &"dropped_item", payload)
			pickup._source_runtime_id = placement.runtime_id
			pickup._source_payload = payload
			delta_root.add_child(pickup)
			pickup.spring(global_position + Vector3.UP * 0.5)
			return

	# Open ocean / no DeltaRoot — transient drop, no delta written.
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
