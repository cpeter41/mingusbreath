# Tests

Automated tests for Mingusbreath, built on **GdUnit4** (pinned to v6.1.3).

## Setup

GdUnit4 is not committed to the repo — install it once per checkout:

```sh
pwsh tests/install_gdunit4.ps1            # POSIX: tests/install_gdunit4.sh
godot --headless --path . --import        # refresh the class cache
```

The install script clones the pinned v6.1.3 tag into `addons/gdUnit4/`
(which is gitignored). CI must run this step before the suite.

## Running

```sh
pwsh tests/run_tests.ps1                                  # whole suite
pwsh tests/run_tests.ps1 unit/world                       # one directory
pwsh tests/run_tests.ps1 unit/world/test_island_placer.gd # one file
```

`run_tests.sh` is the POSIX mirror. Both exit `0` on pass, non-zero on failure,
and write JUnit XML + an HTML report under `tests/.results/` (gitignored).

The Godot binary is taken from `$env:GODOT_PATH`, falling back to the project
default. A few harmless `remote-debug tcp://127.0.0.1:0` lines print at
startup — GdUnit4's runner wiring; ignore them, the exit code is what counts.

## Layout

`tests/` mirrors `scripts/` — a change to `scripts/world/island_placer.gd` is
tested in `tests/unit/world/`.

| Dir            | Contents |
|----------------|----------|
| `unit/`        | Pure logic, no scene tree. Fast. |
| `integration/` | Scene tree + autoload tests. |
| `multiplayer/` | Two-peer host/client harness (planned). |
| `helpers/`     | Shared test code — not scanned as test suites. |
| `fixtures/`    | Test `.tres` data and `golden/` JSON snapshots. |

## Writing a test

A test suite is a `.gd` file whose methods are prefixed `test_`:

```gdscript
extends GdUnitTestSuite              # or: extends GameTest

func test_two_plus_two() -> void:
    assert_int(2 + 2).is_equal(4)
```

Extend **`GameTest`** (`helpers/game_test.gd`) instead of `GdUnitTestSuite`
when the suite needs:

- `assert_deterministic(callable)` — runs a generator twice, asserts identical
  output. The callable must return primitives / Arrays / Dictionaries.
- `assert_golden(actual, name)` — compares against
  `fixtures/golden/<name>.json`. First run records the snapshot and passes;
  review and commit it, after which it is enforced. To update a snapshot
  intentionally, delete the file and re-run.

Other helpers:

- `AutoloadReset` — clears autoload state between tests. Call the relevant
  reset in `before_test()`; autoloads are singletons and leak state otherwise.
- `FakeFactory` / `FakeCombatant` — lightweight stub nodes, no scene loading.
- `TestSeeds` — named world seeds for reproducible generation tests.

## Notes

- After adding a new `class_name` (e.g. a new test base or helper), Godot's
  class cache must be refreshed before the runner sees it:
  `godot --headless --path . --import`.
- The `.claude/hooks/gd-parse-check.ps1` editor hook reports false positives on
  any script that references an autoload or a not-yet-cached `class_name` —
  it parse-checks files in isolation. Trust the GdUnit4 run, not that hook,
  for test files.
