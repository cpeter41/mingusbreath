class_name GameTest
extends GdUnitTestSuite
## Project-specific test base. Extend this instead of GdUnitTestSuite when a
## suite needs determinism or golden-snapshot checks. Pure-logic suites with
## neither may extend GdUnitTestSuite directly.

const GOLDEN_DIR := "res://tests/fixtures/golden/"


## Runs `generator` twice and asserts both calls produce an identical result.
## `generator` must return a value built only from primitives / Arrays /
## Dictionaries — object instances are not comparable across runs.
func assert_deterministic(generator: Callable) -> void:
	var first: Variant = generator.call()
	var second: Variant = generator.call()
	assert_that(second).is_equal(first)


## Compares `actual` against a recorded JSON snapshot in fixtures/golden/.
## First run (snapshot missing): records the snapshot and passes — review and
## commit the generated file, after which the snapshot is enforced.
## To intentionally update a snapshot, delete its file and re-run.
func assert_golden(actual: Variant, snapshot_name: String) -> void:
	var path := GOLDEN_DIR + snapshot_name + ".json"
	var actual_json := JSON.stringify(actual, "\t")

	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(GOLDEN_DIR)
		var w := FileAccess.open(path, FileAccess.WRITE)
		assert_object(w).is_not_null()
		w.store_string(actual_json)
		w.close()
		prints("[golden] recorded new snapshot:", path)
		return

	var r := FileAccess.open(path, FileAccess.READ)
	var golden: Variant = JSON.parse_string(r.get_as_text())
	r.close()
	# Compare parsed structures so JSON formatting never fails the test.
	assert_that(JSON.parse_string(actual_json)).is_equal(golden)
