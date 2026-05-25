extends Node3D

# Fires a harpoon projectile from the bow's Muzzle marker toward the shooter's
# crosshair-aim target (Player.aim_target() — camera raycast). Server-authoritative
# spawn: firing peer RPCs ProjectileManager, host instantiates Harpoon.tscn into
# /World/Projectiles, MultiplayerSpawner replicates it to all peers.

const HARPOON_SPEED := 40.0

@onready var muzzle: Marker3D = $Muzzle


func fire(shooter: Node) -> void:
	if muzzle == null:
		return
	var target: Vector3 = shooter.aim_target() if shooter.has_method("aim_target") \
		else muzzle.global_position + (-muzzle.global_transform.basis.z * 50.0)
	var origin := muzzle.global_position
	var direction := target - origin
	if direction.length_squared() < 0.0001:
		direction = -muzzle.global_transform.basis.z
	direction = direction.normalized()
	# looking_at builds a basis whose -Z faces `direction` — matches the harpoon
	# mesh orientation in Harpoon.tscn so the projectile visually points along
	# its flight path instead of inheriting the bone's arbitrary rotation.
	var xform := Transform3D(
		Basis.looking_at(direction, Vector3.UP),
		origin
	)
	var velocity := direction * HARPOON_SPEED
	var shooter_peer_id: int = shooter.peer_id if "peer_id" in shooter \
		else multiplayer.get_unique_id()
	ProjectileManager.request_spawn_harpoon.rpc_id(1, shooter_peer_id, xform, velocity)
