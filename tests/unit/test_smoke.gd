# Phase 0 smoke test — proves the GdUnit4 runner is wired up and discovers
# suites under tests/. If this fails, the framework install is broken; fix
# that before trusting any other test result.
extends GdUnitTestSuite


func test_runner_is_alive() -> void:
	assert_bool(true).is_true()


func test_arithmetic() -> void:
	assert_int(2 + 2).is_equal(4)


func test_godot_version_is_4() -> void:
	assert_int(Engine.get_version_info()["major"]).is_equal(4)
