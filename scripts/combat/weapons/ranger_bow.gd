extends Node3D

# Fires a harpoon projectile from the bow's Muzzle marker. Server-authoritative
# spawn — the firing peer RPCs ProjectileManager, the host instantiates the
# harpoon into /World/Projectiles, MultiplayerSpawner replicates it to all peers.

const HARPOON_SPEED := 40.0

@onready var muzzle: Marker3D = $Muzzle


func fire(shooter: Node) -> void:
	if muzzle == null:
		return
	var xform := muzzle.global_transform
	var forward := -xform.basis.z.normalized()
	var velocity := forward * HARPOON_SPEED
	var shooter_peer_id: int = shooter.peer_id if "peer_id" in shooter else multiplayer.get_unique_id()
	ProjectileManager.request_spawn_harpoon.rpc_id(1, shooter_peer_id, xform, velocity)
