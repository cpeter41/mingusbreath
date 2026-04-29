extends Node

var regions: Dictionary = {}
var stations: Dictionary = {}

func _ready() -> void:
	SaveSystem.register(self)

func discover_region(chunk_id: Vector2i) -> void:
	regions[chunk_id] = true

func discover_station(station_id: StringName) -> void:
	if not stations.has(station_id):
		stations[station_id] = true
		EventBus.station_discovered.emit(station_id)

func save_data() -> Dictionary:
	return {
		"regions": regions.keys(),
		"stations": stations.keys(),
	}

func load_data(d: Dictionary) -> void:
	regions.clear()
	for k in d.get("regions", []):
		regions[k] = true
	stations.clear()
	for k in d.get("stations", []):
		stations[k] = true
