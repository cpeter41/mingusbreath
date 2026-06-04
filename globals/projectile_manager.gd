extends Node
# Autoload. Server-authoritative spawner for projectiles. Firing peers RPC the
# host; host instantiates into /World/Projectiles where the MultiplayerSpawner
# replicates the spawn to every peer. Mirrors PickupManager / BoatManager style.

const HARPOON_SCENE := preload("res://scenes/weapons/Harpoon.tscn")
const PROJECTILE_SPAWN_LIMIT := 32


@rpc("any_peer", "reliable", "call_local")
func request_spawn_harpoon(shooter_peer_id: int, xform: Transform3D, velocity: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var container := _projectiles_container()
	if container == null or container.get_child_count() >= PROJECTILE_SPAWN_LIMIT:
		return
	var p := HARPOON_SCENE.instantiate()
	p.velocity = velocity
	var shooter := _player_for_peer(shooter_peer_id)
	if shooter != null:
		p.shooter_path = shooter.get_path()
	container.add_child(p, true)
	p.global_transform = xform


func _projectiles_container() -> Node:
	var root := _world_root()
	return root.get_node_or_null("Projectiles") if root != null else null


func _player_for_peer(peer_id: int) -> Node:
	var root := _world_root()
	if root == null:
		return null
	var players := root.get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null("Player_%d" % peer_id)


func _world_root() -> Node:
	# Mirrors NetworkManager._world_root assignment pattern; uses the current
	# scene root since the autoload doesn't hold a direct reference.
	var scene := get_tree().current_scene
	return scene


