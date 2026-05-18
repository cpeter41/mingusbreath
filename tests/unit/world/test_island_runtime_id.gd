# Unit test — IslandRuntimeId (scripts/world/island_runtime_id.gd).
# Runtime ids key per-island delta storage; they must be stable and unique
# per (world_seed, slot_index, def_id).
extends GdUnitTestSuite


func test_format_is_seed_slot_def() -> void:
	assert_str(String(IslandRuntimeId.compute(42, 3, &"isle_a"))).is_equal("42::3::isle_a")


func test_is_deterministic() -> void:
	var a := IslandRuntimeId.compute(7, 1, &"x")
	var b := IslandRuntimeId.compute(7, 1, &"x")
	assert_str(String(a)).is_equal(String(b))


func test_differs_by_slot() -> void:
	var a := String(IslandRuntimeId.compute(7, 1, &"x"))
	var b := String(IslandRuntimeId.compute(7, 2, &"x"))
	assert_str(a).is_not_equal(b)


func test_differs_by_seed() -> void:
	var a := String(IslandRuntimeId.compute(7, 1, &"x"))
	var b := String(IslandRuntimeId.compute(8, 1, &"x"))
	assert_str(a).is_not_equal(b)


func test_differs_by_def_id() -> void:
	var a := String(IslandRuntimeId.compute(7, 1, &"x"))
	var b := String(IslandRuntimeId.compute(7, 1, &"y"))
	assert_str(a).is_not_equal(b)
