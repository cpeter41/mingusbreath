class_name ItemPickup
extends Area3D

@export var item_id: StringName = &""
@export var count: int = 1
func _ready() -> void:
	# Placeholder cube mesh
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.7, 0.2)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# Collision shape on dedicated layer 4 (player-pickup layer)
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.6
	add_child(col)
	collision_layer = 8   # layer 4 (bit 3)
	collision_mask = 1    # detect player CharacterBody3D on layer 1

	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_pickup"):
		body.take_pickup(item_id, count)
		print("[Inventory] slots: ", body.inventory.slots)
		queue_free()
