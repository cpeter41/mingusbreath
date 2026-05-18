extends ChatCommand

func get_name() -> StringName:
	return &"help"

func execute(_args: Array) -> String:
	var names: Array[String] = []
	for cmd in CommandRegistry.all_commands():
		names.append("/" + cmd.get_name())
	names.sort()
	return ", ".join(names)
