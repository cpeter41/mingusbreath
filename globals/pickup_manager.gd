extends Node
# Host-owned pickup spawner. Pickups are server-authoritative and spawn into
# /World/Pickups via the PickupSpawner MultiplayerSpawner, so the host adding a
# pickup there replicates it to every peer.

const PICKUP_SCENE := preload("res://scenes/items/ItemPickup.tscn")
# Must match PickupSpawner.spawn_limit in World.tscn.
const PICKUP_SPAWN_LIMIT := 64


## Server-only. Spawns a configured ItemPickup at world_pos and plays its spring
## hop. No-op on clients — the PickupSpawner replicates the result to them.
func spawn_loot(item_id: StringName, count: int, world_pos: Vector3) -> ItemPickup:
	if not multiplayer.is_server():
		return null
	var container := _pickups_container()
	if container == null:
		push_warning("[PickupManager] /World/Pickups container missing")
		return null
	if container.get_child_count() >= PICKUP_SPAWN_LIMIT:
		push_warning(
			"[PickupManager] pickup spawn_limit (%d) reached; ignoring drop" % PICKUP_SPAWN_LIMIT
		)
		return null
	var pickup := PICKUP_SCENE.instantiate() as ItemPickup
	# Set replicated state before add_child so the synchronizer ships it on spawn.
	pickup.item_id = item_id
	pickup.count = count
	container.add_child(pickup, true)
	pickup.spring(world_pos)
	return pickup


func _pickups_container() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Pickups")
