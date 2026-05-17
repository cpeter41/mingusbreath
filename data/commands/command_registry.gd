extends Node
# Command registry autoload. Acts as the import header for all slash commands:
# every command class is preloaded here so adding a new command means adding
# one const line in the right section and one entry in _build_commands().

# ── Default commands ──────────────────────────────────────────────────────────

# ── Debug commands ────────────────────────────────────────────────────────────

# ── Admin commands ────────────────────────────────────────────────────────────

# StringName → ChatCommand instance (aliases also mapped here).
var _commands: Dictionary = {}


func _ready() -> void:
	for cmd in _build_commands():
		_commands[cmd.get_name()] = cmd
		for alias in cmd.get_aliases():
			_commands[alias] = cmd
	EventBus.chat_command_entered.connect(_on_command_entered)


# Returns deduplicated list of registered commands (one entry per command, no aliases).
func all_commands() -> Array:
	var seen: Array = []
	for cmd in _commands.values():
		if cmd not in seen:
			seen.append(cmd)
	return seen


func _build_commands() -> Array:
	return []


func _on_command_entered(text: String) -> void:
	var parts := text.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return
	var cmd_name := StringName(parts[0].to_lower())
	var args: Array = Array(parts.slice(1))
	var cmd: ChatCommand = _commands.get(cmd_name, null)
	if cmd == null:
		_reply("Unknown command: /%s" % parts[0])
		return
	var reply := cmd.execute(args)
	if not reply.is_empty():
		_reply(reply)


func _reply(text: String) -> void:
	EventBus.chat_message_received.emit("[System]", text)
