# Integration test — WorldStream (globals/world_stream.gd).
# Covers the read-only query helpers against the live autoload. Full tier
# load/unload needs island scenes — see TEST_EXPANSION_PLAN.md Phase 8.
extends GdUnitTestSuite


func test_delta_store_exists_after_ready() -> void:
	assert_object(WorldStream.get_delta_store()).is_not_null()


func test_far_instance_for_unknown_island_is_null() -> void:
	assert_object(WorldStream.get_far_instance(&"no_such_island")).is_null()


func test_delta_root_for_unknown_island_is_null() -> void:
	assert_object(WorldStream.get_delta_root(&"no_such_island")).is_null()


func test_placement_enclosing_origin_is_null_with_no_islands() -> void:
	# No island is anchored at the world origin, so nothing encloses it.
	assert_object(WorldStream.get_placement_enclosing(Vector3.ZERO)).is_null()


func test_active_biome_without_player_falls_back_to_ocean() -> void:
	# With no player set, get_active_biome() returns the ocean fallback biome.
	assert_object(WorldStream.get_active_biome()).is_not_null()
