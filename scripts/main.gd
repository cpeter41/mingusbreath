extends Node

@onready var _label: Label = $CanvasLayer/Label

func _ready() -> void:
	SaveSystem.load_or_init()
	_label.text = "Mingusbreath — skeleton OK | last_played: %d" % GameState.last_played_at

func _exit_tree() -> void:
	GameState.last_played_at = int(Time.get_unix_time_from_system())
	SaveSystem.save()
