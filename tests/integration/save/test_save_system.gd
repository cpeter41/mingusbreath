# Integration test — SaveSystem (globals/save_system.gd).
# World-slot save/load roundtrip and default-on-missing behavior, run against
# the live autoload and a temporary user://worlds slot.
extends GdUnitTestSuite


# Minimal Saveable: round-trips one int. load_data({}) yields the -1 sentinel.
class FakeSaveable extends Node:
	var value: int = 0

	func save_data() -> Dictionary:
		return {"value": value}

	func load_data(d: Dictionary) -> void:
		value = int(d.get("value", -1))


var _slot: String
var _fake: FakeSaveable
var _baseline: Dictionary  # Node -> save_data() snapshot of the real autoloads


func before_test() -> void:
	# load_or_init() defaults EVERY registered saveable. Snapshot the real
	# autoloads first so this suite cannot leak state into other suites.
	_baseline = {}
	for n in SaveSystem._saveables:
		if is_instance_valid(n) and n.has_method("save_data"):
			_baseline[n] = n.save_data()

	_slot = SaveSystem.create_world("test_world")
	SaveSystem.set_world(_slot)

	_fake = auto_free(FakeSaveable.new())
	_fake.name = "FakeSaveable"
	SaveSystem.register(_fake)

	# Establishes _is_world_owner (offline peer == server == owner), which save()
	# requires before it will write anything.
	SaveSystem.load_or_init()


func after_test() -> void:
	SaveSystem.delete_save()
	SaveSystem._saveables.erase(_fake)  # un-register the about-to-be-freed stub
	for n in _baseline:
		if is_instance_valid(n) and n.has_method("load_data"):
			n.load_data(_baseline[n])


func test_save_then_load_restores_value() -> void:
	_fake.value = 77
	assert_bool(SaveSystem.save()).is_true()
	_fake.value = 0
	SaveSystem.load_or_init()
	assert_int(_fake.value).is_equal(77)


func test_load_with_no_save_file_applies_defaults() -> void:
	_fake.value = 42
	SaveSystem.delete_save()  # ensure the slot file is absent
	SaveSystem.load_or_init()
	assert_int(_fake.value).is_equal(-1)  # load_data({}) sentinel


func test_save_leaves_no_stray_temp_file() -> void:
	_fake.value = 5
	SaveSystem.save()
	assert_bool(
		FileAccess.file_exists(SaveSystem.WORLDS_DIR + _slot + ".tmp")
	).is_false()


func test_save_with_no_world_selected_fails() -> void:
	SaveSystem.set_world("")
	assert_bool(SaveSystem.save()).is_false()
	SaveSystem.set_world(_slot)  # restore so after_test cleans the right slot
