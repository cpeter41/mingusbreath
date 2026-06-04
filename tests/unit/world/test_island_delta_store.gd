# Unit test — IslandDeltaStore (scripts/world/island_delta_store.gd).
# Per-island delta storage keyed by runtime_id, with StringName-safe persistence.
extends GdUnitTestSuite

const ISLAND_A := &"1234::3::isle_a"
const ISLAND_B := &"1234::4::isle_b"
const TYPE := &"item_taken"


func _store() -> IslandDeltaStore:
	# Not added to the scene tree, so _ready() (SaveSystem.register) never runs.
	return auto_free(IslandDeltaStore.new())


func test_add_then_get_returns_delta() -> void:
	var s := _store()
	s.add_delta(ISLAND_A, TYPE, {"slot": 2})
	var by_type := s.get_deltas_for(ISLAND_A)
	assert_dict(by_type).contains_keys([TYPE])
	assert_array(by_type[TYPE]).is_equal([{"slot": 2}])


func test_get_for_unknown_island_is_empty() -> void:
	assert_dict(_store().get_deltas_for(&"missing")).is_empty()


func test_multiple_deltas_of_same_type_accumulate() -> void:
	var s := _store()
	s.add_delta(ISLAND_A, TYPE, {"slot": 1})
	s.add_delta(ISLAND_A, TYPE, {"slot": 2})
	assert_array(s.get_deltas_for(ISLAND_A)[TYPE]).has_size(2)


func test_remove_match_removes_exact_payload() -> void:
	var s := _store()
	s.add_delta(ISLAND_A, TYPE, {"slot": 2})
	assert_bool(s.remove_delta_match(ISLAND_A, TYPE, {"slot": 2})).is_true()
	# Second removal finds nothing — the entry is already gone.
	assert_bool(s.remove_delta_match(ISLAND_A, TYPE, {"slot": 2})).is_false()


func test_remove_match_ignores_non_matching_payload() -> void:
	var s := _store()
	s.add_delta(ISLAND_A, TYPE, {"slot": 2})
	assert_bool(s.remove_delta_match(ISLAND_A, TYPE, {"slot": 99})).is_false()
	assert_array(s.get_deltas_for(ISLAND_A)[TYPE]).has_size(1)


func test_clear_island_drops_all_deltas() -> void:
	var s := _store()
	s.add_delta(ISLAND_A, TYPE, {"slot": 1})
	s.clear_island(ISLAND_A)
	assert_dict(s.get_deltas_for(ISLAND_A)).is_empty()


func test_save_load_roundtrip_preserves_data_and_keys() -> void:
	var s := _store()
	s.add_delta(ISLAND_A, TYPE, {"slot": 9})
	s.add_delta(ISLAND_B, &"dropped_item", {"item_id": "log", "count": 3})

	var restored := _store()
	restored.load_data(s.save_data())
	assert_array(restored.get_deltas_for(ISLAND_A)[TYPE]).is_equal([{"slot": 9}])
	assert_dict(restored.get_deltas_for(ISLAND_B)).contains_keys([&"dropped_item"])
