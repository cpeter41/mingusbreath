class_name ChatCommand
extends RefCounted
# Base class for all slash commands. Subclass and override get_name / execute.
# The registry calls execute() and shows the returned string locally as a
# [System] message. Return "" to stay silent.

func get_name() -> StringName:
	return &""

# Additional aliases that also route to this command (e.g. &"tod" for &"time").
func get_aliases() -> Array[StringName]:
	return []

# Category controls who may run this command. Must match one of the subfolder
# names: &"default" (all players), &"debug" (all players for now),
# &"admin" (host / solo only). Override in subclasses placed in debug/ or admin/.
func get_category() -> StringName:
	return &"default"

# args is the tokenised remainder after the command name (space-split, no "/").
func execute(_args: Array) -> String:
	return ""
