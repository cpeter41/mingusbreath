extends Node
# Host-owned registry of last-known player positions. Part of the world save
# (save.dat) — distinct from ProfileSave, which holds per-peer skills/inventory.
#
# Keyed by a stable id (Steam id when available, else peer id) so a returning
# player lands where they left off. Only the host reads/writes this; guests
# receive their spawn position via the set_spawn_position RPC on their Player.

var positions: Dictionary = {}  # stable_id (String) -> { "pos": Vector3, "rot_y": float }


func _ready() -> void:
	SaveSystem.register(self)


func record(stable_id: String, pos: Vector3, rot_y: float) -> void:
	positions[stable_id] = {"pos": pos, "rot_y": rot_y}


## Returns {} if no record exists for this id.
func get_record(stable_id: String) -> Dictionary:
	return positions.get(stable_id, {})


func save_data() -> Dictionary:
	var out := {}
	for k in positions:
		out[k] = {
			"pos": V3Codec.encode(positions[k]["pos"]),
			"rot_y": positions[k]["rot_y"],
		}
	return {"positions": out}


func load_data(d: Dictionary) -> void:
	positions.clear()
	var stored: Dictionary = d.get("positions", {})
	for k in stored:
		positions[k] = {
			"pos": V3Codec.decode(stored[k]["pos"]),
			"rot_y": float(stored[k].get("rot_y", 0.0)),
		}
