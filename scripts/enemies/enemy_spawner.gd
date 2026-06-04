extends MultiplayerSpawner
# Attached to /World/EnemySpawner. Custom spawn function lets a single generic
# Enemy.tscn cover every monster variant — the spawn payload is the def id, and
# both host and replicating clients resolve it via EnemyRegistry to set
# Enemy.def before _ready() runs. Without this indirection every variant would
# need its own .tscn just to bake in a different EnemyDef ext_resource.

const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")


func _ready() -> void:
	spawn_function = _spawn_enemy


## Runs on host (when spawn() is called) and on each client (when the spawn
## packet replicates in). Returns the configured node; MultiplayerSpawner
## parents it under spawn_path.
func _spawn_enemy(data: Variant) -> Node:
	var def_id := StringName(str(data))
	var e: Node = ENEMY_SCENE.instantiate()
	e.def = EnemyRegistry.resolve(def_id)
	return e
