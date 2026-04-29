extends Node

var world_seed: int = 0
var paused: bool = false
var last_played_at: int = 0

func _ready() -> void:
	SaveSystem.register(self)

func save_data() -> Dictionary:
	return {
		"world_seed": world_seed,
		"last_played_at": last_played_at,
	}

func load_data(d: Dictionary) -> void:
	world_seed = int(d.get("world_seed", 0))
	last_played_at = int(d.get("last_played_at", 0))
