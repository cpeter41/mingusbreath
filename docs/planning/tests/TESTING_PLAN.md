# Testing System Plan — Mingusbreath

Godot 4.6 / GDScript. Plan for an agent-runnable, human-readable test suite.

## Goal

A CLI-runnable test suite agents invoke after any change, with a clear pass/fail
exit code and machine-readable output. Modular layout mirroring `scripts/`,
human-readable helpers, low friction to add a test.

## Framework choice: GdUnit4

Use **GdUnit4** (`addons/gdUnit4/`, vendored + version-pinned).

Reasons:

- Built-in scene runner, input simulation, parameterized + fuzz tests.
- Rich fluent asserts (`assert_that(x).is_equal(...)`), type-specific matchers.
- First-class VS Code extension — run/debug from editor, gutter icons.
- CLI runner + JUnit/HTML reports; clean exit codes for agents and CI.
- Active development, good Godot 4.6 support.

GUT was considered (simpler API, named in the original CLAUDE.md). Rejected:
its scene/parameterized testing is weaker, which costs us in the Phase 3–4
scene and multiplayer suites. The directory layout and phasing below are
framework-agnostic — only the assert syntax and addon differ.

## Directory layout

```
tests/
  .gdunit_config            GdUnit4 config — dirs, report path
  run_tests.ps1             canonical entrypoint (Windows)
  run_tests.sh              POSIX mirror
  README.md                 how to write + run tests

  helpers/
    game_test.gd            base class: class_name GameTest extends GdUnitTestSuite
    fake_factory.gd         builds minimal stub nodes (fake Player, fake target)
    autoload_reset.gd       resets autoload state between tests
    seeds.gd                named deterministic seed constants

  fixtures/                 .tres test data, recorded golden snapshots

  unit/                     pure logic, no scene tree — fast
    world/                  test_island_placement.gd, test_island_runtime_id.gd, test_island_placer.gd
    combat/                 test_combat_resolver.gd
    util/                   test_v3_codec.gd
    inventory/              test_inventory.gd
    data/                   test_def_resources.gd (schema sanity)

  integration/              needs scene tree / autoloads
    save/                   test_save_roundtrip.gd, test_island_delta_store.gd
    world/                  test_world_stream.gd
    player/                 test_state_machines.gd

  multiplayer/              host+client harness (Phase 4, scaffold only)
    test_mp_smoke.gd
```

`tests/` subdirs mirror `scripts/` so an agent editing
`scripts/world/island_placement.gd` knows to look in `tests/unit/world/`.

## Core building blocks

### 1. `GameTest` base class

`class_name GameTest extends GdUnitTestSuite`. Project-specific conveniences so
individual test files stay short and readable:

- `assert_deterministic(callable, seed)` — runs a generator twice, asserts
  identical output.
- `assert_golden(actual, fixture_name)` — compares against a recorded snapshot
  in `fixtures/`; regenerate-on-flag for golden updates.
- Shared `before_test` / `after_test` that call `autoload_reset.gd`.

### 2. Autoload isolation

Autoloads (`GameState`, `SkillManager`, `IslandRegistry`, etc.) are singletons
that persist across tests — state leaks between tests otherwise.
`autoload_reset.gd` exposes `reset_all()` and per-system resets
(`reset_game_state()`, `reset_skills()`), called in `before_test`. Where an
autoload has no clean reset path, add a `_reset_for_test()` method to the
autoload — cheap, also useful for "new game".

### 3. `fake_factory.gd`

Combat/player code takes `Node` params. Tests need lightweight stand-ins
without loading full `Player.tscn`. The factory builds minimal stubs: a fake
attacker/target exposing only `take_damage`, `is_multiplayer_authority`, HP.
Keeps unit tests scene-free and fast.

### 4. Deterministic / golden tests

The architecture leans hard on seed-determinism. Dedicated coverage:

- Same `world_seed` → identical island placement, identical `runtime_id` hashes.
- Golden-master: record placement output for fixed seeds in `fixtures/`, fail
  on drift.
- Highest-value suite — a determinism regression silently corrupts every save.

## CLI runner — the agent entrypoint

`tests/run_tests.ps1`:

- Resolves the Godot binary from `$env:GODOT_PATH`, falling back to the same
  default path the existing `.claude/hooks/gd-parse-check.ps1` hook uses.
- Runs GdUnit4's headless runner against `tests/`, writing JUnit XML under
  `tests/.results/`.
- Propagates the runner's exit code so agents (and CI) read pass/fail directly.
- Accepts an optional path arg to run one dir/file
  (`run_tests.ps1 unit/world`) — fast iteration.

`run_tests.sh` mirrors it for POSIX.

## Multiplayer testing (Phase 4 — scaffold only)

Host-authoritative MP is the hardest to test. Plan, not commit:

- A meta-runner launches two headless processes (`--offline --host`,
  `--offline --join 127.0.0.1`), scrapes log output, asserts on roster /
  spawn / save events.
- Start with one smoke test (peers connect, both spawn a `Player`). Expand
  later.
- Kept in its own dir so it can be excluded from the fast unit run.

## Agent integration

- **One command**: agents run `pwsh tests/run_tests.ps1`. Documented as the
  canonical post-change step in CLAUDE.md.
- **Permissions**: add the test-run invocation to the `.claude/settings.json`
  allow-list.
- **CLAUDE.md**: Tests section documents run instructions + the "add a test in
  the mirrored dir" convention. (Done.)
- **Optional hook**: a `Stop` hook running the unit suite after an agent
  session — modelled on the existing `gd-parse-check.ps1` PostToolUse hook.
  Kept optional; full-run latency may annoy on tiny edits, and the parse-check
  hook already covers per-edit syntax.
- **JUnit XML** output lets a future CI step or hook parse failures
  structurally.

## Phasing

| Phase | Deliverable | Verifies |
|-------|-------------|----------|
| 0 | Vendor GdUnit4, `.gdunit_config`, `run_tests.ps1`, one smoke test | CLI runner works headless, exit code correct |
| 1 | Unit tests: `island_placement`, `island_runtime_id`, `v3_codec`, `combat_resolver`, `inventory` | Pure-logic coverage |
| 2 | `game_test.gd`, `fake_factory.gd`, `autoload_reset.gd`, `fixtures/` + golden determinism tests | Reusable harness, determinism guard |
| 3 | Integration: save roundtrip, `island_delta_store`, `world_stream`, state machines | Scene-tree + autoload coverage |
| 4 | Multiplayer harness scaffold + smoke test | Two-peer connect/spawn |
| 5 | CLAUDE.md + permissions + `tests/README.md` | Agent workflow documented |

## First test targets (best ROI, mostly pure logic)

- `scripts/world/island_placement.gd` + `island_runtime_id.gd` — determinism core.
- `scripts/combat/combat_resolver.gd` — small, pure math, easy win
  (`base * (1 + 0.1 * (level - 1))`).
- `scripts/util/v3_codec.gd` — encode/decode roundtrip.
- `scripts/inventory/inventory.gd` — add/remove/stack logic.
- `data/*.tres` schema sanity — every Resource loads, required fields non-null.

## Open questions

1. Pin a GdUnit4 version, or vendor latest? (Recommend pin + commit.)
2. Stop-hook auto-run, or manual-only? (Recommend manual + documented; the
   parse-check hook already guards syntax.)
3. Multiplayer harness — build now, or defer until the MP save-split phase
   lands? (Recommend scaffold only.)
