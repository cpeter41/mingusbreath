## Bitmask values for physics layer/mask fields. Mirrors project.godot [layer_names/3d_physics].
class_name CollisionLayers

const WORLD: int      = 1   # bit 0 — terrain, players, enemies, default physics
const HITBOX: int     = 2   # bit 1 — active swing volumes
const HURTBOX: int    = 4   # bit 2 — passive damage receivers
const SHORE_WALL: int = 8   # bit 3 — shore wall (boats only); pickups also live here
