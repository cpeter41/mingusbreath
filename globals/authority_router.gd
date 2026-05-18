extends Node
# Helper to keep `if multiplayer.is_server()` boilerplate out of every script.
# See MULTIPLAYER_RETROFIT_PLAN.md Authority Rules.


func _ready() -> void:
	print("[AuthorityRouter] ready")


## Run callable only if this peer is the server (or game is offline).
func server_only(c: Callable) -> Variant:
	if NetworkManager.is_offline() or multiplayer.is_server():
		return c.call()
	return null


## Run callable only if this peer owns the given node's multiplayer authority.
func owner_only(node: Node, c: Callable) -> Variant:
	if NetworkManager.is_authority_for(node):
		return c.call()
	return null


## Connect signal handler only on the authority for the given node.
## Useful for "only server reacts to area_entered on this hitbox" patterns.
func on_authority(node: Node, signal_name: StringName, target: Callable) -> void:
	if NetworkManager.is_authority_for(node):
		node.connect(signal_name, target)


## True if this peer should run AI / world simulation logic for the given node.
## Currently identical to is_authority_for; kept separate so semantics can diverge.
func should_simulate(node: Node) -> bool:
	return NetworkManager.is_authority_for(node)
