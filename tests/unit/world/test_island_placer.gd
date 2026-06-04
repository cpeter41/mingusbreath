# Unit test — IslandPlacer (scripts/world/island_placer.gd).
# Placement must be fully deterministic from the world seed. Defs are built
# in-test with the default EASY difficulty so the empty ZoneMap (classify ->
# EASY) always satisfies the zone-match pass.
extends GameTest

const SEED := TestSeeds.DEFAULT
const WORLD_SIZE := 6000.0
const ISLAND_COUNT := 8


func before_test() -> void:
	# Empty zones -> ZoneMap.classify() returns EASY for every point.
	AutoloadReset.reset_zones()


func _make_def(id: StringName, radius: float, weight: float) -> IslandDef:
	var d := IslandDef.new()
	d.id = id
	d.footprint_radius = radius
	d.placement_weight = weight
	return d


func _defs() -> Array:
	return [
		_make_def(&"island_mainland_01", 300.0, 1.0),
		_make_def(&"isle_cove", 80.0, 1.0),
		_make_def(&"isle_reef", 60.0, 1.0),
		_make_def(&"isle_peak", 100.0, 1.0),
	]


# Converts placements to a plain primitive structure — comparable across runs
# and JSON-serializable for golden snapshots.
func _to_data(placements: Array) -> Array:
	var out: Array = []
	for p in placements:
		out.append({
			"id": String(p.def.id),
			"slot": p.slot_index,
			"x": snappedf(p.position.x, 0.001),
			"z": snappedf(p.position.z, 0.001),
			"rot": snappedf(p.rotation_y, 0.001),
			"runtime_id": String(p.runtime_id),
		})
	return out


func test_slot_zero_is_mainland() -> void:
	var placements := IslandPlacer.place(_defs(), SEED, WORLD_SIZE, ISLAND_COUNT)
	assert_int(placements.size()).is_greater(0)
	assert_str(String(placements[0].def.id)).is_equal("island_mainland_01")
	assert_int(placements[0].slot_index).is_equal(0)


func test_placement_is_deterministic() -> void:
	assert_deterministic(func() -> Array:
		return _to_data(IslandPlacer.place(_defs(), SEED, WORLD_SIZE, ISLAND_COUNT)))


func test_different_seed_changes_layout() -> void:
	var a := _to_data(IslandPlacer.place(_defs(), TestSeeds.DEFAULT, WORLD_SIZE, ISLAND_COUNT))
	var b := _to_data(IslandPlacer.place(_defs(), TestSeeds.ALT, WORLD_SIZE, ISLAND_COUNT))
	assert_that(a).is_not_equal(b)


func test_no_islands_overlap() -> void:
	var placements := IslandPlacer.place(_defs(), SEED, WORLD_SIZE, ISLAND_COUNT)
	for i in placements.size():
		for j in range(i + 1, placements.size()):
			var a = placements[i]
			var b = placements[j]
			var min_dist: float = a.def.footprint_radius + b.def.footprint_radius
			assert_float(a.position.distance_to(b.position)).is_greater(min_dist)


func test_matches_golden_layout() -> void:
	var data := _to_data(IslandPlacer.place(_defs(), SEED, WORLD_SIZE, ISLAND_COUNT))
	assert_golden(data, "island_layout_default")
