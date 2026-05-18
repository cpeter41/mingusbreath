# Unit test — Inventory (scripts/inventory/inventory.gd).
# Item ids unknown to InventoryRegistry fall back to a 99-item max stack, so
# these tests use unregistered ids for predictable stacking math.
extends GdUnitTestSuite

const UNKNOWN := &"test_unknown_item"
const STACK := 99  # InventoryRegistry fallback max_stack for unknown items


func _new_inventory() -> Inventory:
	return auto_free(Inventory.new())


func test_add_within_one_stack() -> void:
	var inv := _new_inventory()
	assert_int(inv.add(UNKNOWN, 10)).is_equal(0)  # nothing left over
	assert_int(inv.count_of(UNKNOWN)).is_equal(10)
	assert_int(inv.slots.size()).is_equal(1)


func test_add_spans_multiple_stacks() -> void:
	var inv := _new_inventory()
	inv.add(UNKNOWN, 250)  # 99 + 99 + 52
	assert_int(inv.count_of(UNKNOWN)).is_equal(250)
	assert_int(inv.slots.size()).is_equal(3)


func test_add_overflow_returns_leftover() -> void:
	var inv := _new_inventory()
	var capacity := Inventory.MAX_SLOTS * STACK  # 20 * 99 = 1980
	assert_int(inv.add(UNKNOWN, capacity + 20)).is_equal(20)
	assert_int(inv.count_of(UNKNOWN)).is_equal(capacity)


func test_remove_partial_keeps_remainder() -> void:
	var inv := _new_inventory()
	inv.add(UNKNOWN, 50)
	assert_bool(inv.remove(UNKNOWN, 20)).is_true()
	assert_int(inv.count_of(UNKNOWN)).is_equal(30)


func test_remove_more_than_present_fails_without_mutation() -> void:
	var inv := _new_inventory()
	inv.add(UNKNOWN, 5)
	assert_bool(inv.remove(UNKNOWN, 6)).is_false()
	assert_int(inv.count_of(UNKNOWN)).is_equal(5)


func test_remove_drops_emptied_slot() -> void:
	var inv := _new_inventory()
	inv.add(UNKNOWN, STACK)
	inv.remove(UNKNOWN, STACK)
	assert_int(inv.slots.size()).is_equal(0)


func test_save_load_roundtrip() -> void:
	var inv := _new_inventory()
	inv.add(UNKNOWN, 120)
	inv.add(&"other_unknown_item", 5)
	var data := inv.save_data()

	var restored := _new_inventory()
	restored.load_data(data)
	assert_int(restored.count_of(UNKNOWN)).is_equal(120)
	assert_int(restored.count_of(&"other_unknown_item")).is_equal(5)
