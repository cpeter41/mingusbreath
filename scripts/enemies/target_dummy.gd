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
