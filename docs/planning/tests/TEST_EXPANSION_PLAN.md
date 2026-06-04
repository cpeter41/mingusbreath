# Test Coverage Expansion Plan — Mingusbreath

Continues `TESTING_PLAN.md`. Assumes Phases 0–5 are complete: GdUnit4 installed,
`run_tests.ps1` working, unit suite + `GameTest` helpers in place, the
`integration/` and `multiplayer/` directories scaffolded, docs landed.

This plan adds **Phases 6–9** — roughly 65 new test cases — taking the suite
from the deterministic core into persistence, behavior, world simulation, and
multiplayer. Each phase lists test suites with boilerplate to fill in.

Conventions: suites mirror `scripts/` under `tests/`. Pure-logic suites
`extends GdUnitTestSuite`; suites needing determinism/golden helpers
`extends GameTest`. Reset mutated autoloads in `before_test()` via
`AutoloadReset`.

## Phase 6 — Persistence & autoload state

The save/load path is the highest-risk untested surface: a regression here
silently corrupts player worlds.

### `tests/integration/save/test_save_system.gd`

```gdscript
# Save/load roundtrip, schema-version handling, and atomic-write behavior.
extends GameTest

const SLOT := "test_world"

# A minimal Saveable: round-trips a single int.
class FakeSaveable extends Node:
	var value: int = 0
	func save_data() -> Dictionary: return {"value": value}
	func load_data(d: Dictionary) -> void: value = int(d.get("value", -1))

func before_test() -> void:
	SaveSystem.set_world(SaveSystem.create_world(SLOT))

func after_test() -> void:
	SaveSystem.delete_save()

func test_roundtrip_restores_registered_saveable() -> void:
	var s := auto_free(FakeSaveable.new())
	s.name = "FakeSaveable"
	s.value = 77
	SaveSystem.register(s)
	assert_bool(SaveSystem.save()).is_true()
	s.value = 0
	SaveSystem.load_or_init()
	assert_int(s.value).is_equal(77)

func test_missing_slot_loads_defaults() -> void:
	var s := auto_free(FakeSaveable.new())
	s.name = "FakeSaveable"
	s.value = 5
	SaveSystem.register(s)
	SaveSystem.delete_save()
	SaveSystem.load_or_init()       # load_data({}) -> value = -1
	assert_int(s.value).is_equal(-1)

func test_stale_schema_version_wipes_and_defaults() -> void:
	# Write a blob tagged with an impossible version, then load.
	# Expect: file wiped, saveables get load_data({}).
	# TODO: write blob via FileAccess at SaveSystem path with header.version = 99.

func test_guest_save_is_noop() -> void:
	# With _is_world_owner == false, save() must return true and write nothing.
	# TODO: drive SaveSystem into a non-owner state and assert the slot file
	# is unchanged.
```

### `tests/unit/world/test_island_delta_store.gd`

```gdscript
# Per-island delta storage keyed by runtime_id.
extends GdUnitTestSuite

const RID := &"1234::3::isle_a"
const TYPE := &"item_taken"

func _store() -> IslandDeltaStore:
	return auto_free(IslandDeltaStore.new())

func test_add_then_get_returns_delta() -> void:
	var s := _store()
	s.add_delta(RID, TYPE, {"slot": 2})
	assert_dict(s.get_deltas_for(RID)).contains_keys([TYPE])

func test_remove_match_removes_exact_payload() -> void:
	var s := _store()
	s.add_delta(RID, TYPE, {"slot": 2})
	assert_bool(s.remove_delta_match(RID, TYPE, {"slot": 2})).is_true()
	assert_bool(s.remove_delta_match(RID, TYPE, {"slot": 2})).is_false()

func test_clear_island_drops_all_deltas() -> void:
	var s := _store()
	s.add_delta(RID, TYPE, {"slot": 1})
	s.clear_island(RID)
	assert_dict(s.get_deltas_for(RID)).is_empty()

func test_save_load_roundtrip_preserves_stringname_keys() -> void:
	var s := _store()
	s.add_delta(RID, TYPE, {"slot": 9})
	var restored := _store()
	restored.load_data(s.save_data())
	assert_dict(restored.get_deltas_for(RID)).contains_keys([TYPE])
```

### `tests/unit/skills/test_skill_manager.gd`

```gdscript
# XP accumulation and cumulative-curve level derivation.
extends GdUnitTestSuite

const SKILL := &"test_skill"

func after_test() -> void:
	AutoloadReset.reset_skills()

func test_unseen_skill_is_level_1() -> void:
	assert_int(SkillManager.get_level(SKILL)).is_equal(1)

func test_xp_crosses_a_single_threshold() -> void:
	# Curve default [10,30,80,...]; 15 xp -> level 2.
	SkillManager.add_xp(SKILL, 15.0)
	assert_int(SkillManager.get_level(SKILL)).is_greater_equal(2)

func test_multi_level_jump_emits_signal_per_level() -> void:
	var monitor := monitor_signals(EventBus)
	SkillManager.add_xp(SKILL, 1000.0)   # vaults several thresholds at once
	# TODO: assert EventBus.skill_leveled fired once per level gained.

func test_save_load_roundtrip() -> void:
	SkillManager.add_xp(SKILL, 50.0)
	var data := SkillManager.save_data()
	AutoloadReset.reset_skills()
	SkillManager.load_data(data)
	assert_int(SkillManager.get_level(SKILL)).is_greater_equal(2)
```

### `tests/unit/world/test_time_of_day.gd`

```gdscript
# Day-phase boundaries and host/guest time sync.
extends GdUnitTestSuite

func _phase_at(hour: float) -> int:
	TimeOfDay.load_data({"game_minutes": hour * 60.0})
	return TimeOfDay.phase

func test_phase_boundaries() -> void:
	assert_int(_phase_at(6.0)).is_equal(TimeOfDay.Phase.DAWN)
	assert_int(_phase_at(12.0)).is_equal(TimeOfDay.Phase.DAY)
	assert_int(_phase_at(19.0)).is_equal(TimeOfDay.Phase.DUSK)
	assert_int(_phase_at(2.0)).is_equal(TimeOfDay.Phase.NIGHT)

func test_sync_time_applies_server_clock() -> void:
	TimeOfDay.sync_time(9.0 * 60.0, 1.0)
	assert_float(TimeOfDay.game_minutes).is_equal_approx(540.0, 0.001)

func test_load_data_defaults_to_morning() -> void:
	TimeOfDay.load_data({})
	assert_float(TimeOfDay.game_minutes).is_equal_approx(480.0, 0.001)
```

**Phase 6 target: ~20 cases.**

## Phase 7 — Behavior, FSM, commands

### `tests/unit/shared/test_state_machine.gd`

```gdscript
# Transition rules: exit-then-enter, ignore unknown, ignore re-entry.
extends GdUnitTestSuite

class SpyState extends BaseState:
	var entered := 0
	var exited := 0
	func enter() -> void: entered += 1
	func exit() -> void: exited += 1

func _machine_with(states: Dictionary) -> StateMachine:
	var sm := auto_free(StateMachine.new())
	sm._states = states            # test seam; states keyed by name
	return sm

func test_transition_runs_exit_then_enter() -> void:
	var a := SpyState.new(); var b := SpyState.new()
	var sm := _machine_with({"a": a, "b": b})
	sm.transition_to("a")
	sm.transition_to("b")
	assert_int(a.exited).is_equal(1)
	assert_int(b.entered).is_equal(1)

func test_unknown_state_is_noop() -> void:
	var a := SpyState.new()
	var sm := _machine_with({"a": a})
	sm.transition_to("a")
	sm.transition_to("does_not_exist")
	assert_str(sm.current_state_name()).is_equal("a")

func test_reentry_to_current_state_is_noop() -> void:
	var a := SpyState.new()
	var sm := _machine_with({"a": a})
	sm.transition_to("a")
	sm.transition_to("a")
	assert_int(a.entered).is_equal(1)   # not re-entered
```

### `tests/integration/enemies/test_enemy_fsm.gd`

```gdscript
# Enemy AI state transitions driven by a placed target.
extends GdUnitTestSuite

# Uses GdUnit4's scene_runner to step physics frames.
func test_idle_to_sense_when_target_in_range() -> void:
	# TODO: instance the enemy scene, place a FakeCombatant inside sense
	# radius, run a few physics frames, assert the movement FSM left Idle.

func test_chase_to_flee_at_low_hp() -> void:
	# TODO: instance enemy, set hp below flee threshold, assert Flee state.

func test_returns_home_when_target_lost() -> void:
	# TODO: enter Chase, remove the target, assert transition to Return.
```

### `tests/integration/commands/test_command_registry.gd`

```gdscript
# Command parsing, dispatch, aliases, permission gating.
extends GdUnitTestSuite

func _run(text: String) -> String:
	var got := [""]
	var cb := func(_who: String, msg: String) -> void: got[0] = msg
	EventBus.chat_message_received.connect(cb)
	EventBus.chat_command_entered.emit(text)
	EventBus.chat_message_received.disconnect(cb)
	return got[0]

func test_unknown_command_replies_with_error() -> void:
	assert_str(_run("/notacommand")).contains("Unknown command")

func test_known_command_dispatches() -> void:
	# /help is registered — expect a non-empty, non-error reply.
	assert_str(_run("/help")).is_not_equal("")

func test_empty_input_is_noop() -> void:
	assert_str(_run("/")).is_equal("")

func test_all_commands_dedups_aliases() -> void:
	var cmds := CommandRegistry.all_commands()
	assert_int(cmds.size()).is_equal(cmds.size())  # no duplicate instances
```

### `tests/unit/net/test_authority_router.gd`

```gdscript
# Authority helpers in the offline (solo) case.
extends GdUnitTestSuite

func test_server_only_runs_callable_when_offline() -> void:
	var ran := [false]
	AuthorityRouter.server_only(func() -> void: ran[0] = true)
	assert_bool(ran[0]).is_true()

func test_should_simulate_matches_authority() -> void:
	var n := auto_free(Node.new())
	assert_bool(AuthorityRouter.should_simulate(n)) \
		.is_equal(NetworkManager.is_authority_for(n))
```

**Phase 7 target: ~22 cases.**

## Phase 8 — World, generation, physics, data

### `tests/unit/world/test_zone_generator.gd`

```gdscript
# Difficulty-zone generation must be seed-deterministic.
extends GameTest

func test_zone_generation_is_deterministic() -> void:
	assert_deterministic(func() -> Array:
		return _zones_to_data(ZoneGenerator.generate(TestSeeds.DEFAULT, 6000.0)))

func test_matches_golden_zones() -> void:
	var data := _zones_to_data(ZoneGenerator.generate(TestSeeds.DEFAULT, 6000.0))
	assert_golden(data, "zones_default")

# func _zones_to_data(zones: Array) -> Array: ... serialize to primitives
```

### `tests/integration/world/test_world_stream.gd`

```gdscript
# Distance-based island load/unload around the player.
extends GdUnitTestSuite

func test_island_loads_within_radius() -> void:
	# TODO: position a streaming origin near an island anchor, tick WorldStream,
	# assert the island node is present.

func test_island_unloads_when_far() -> void:
	# TODO: move origin well past the unload distance, assert the node freed.
```

### `tests/integration/ships/test_buoyancy.gd`

```gdscript
# Buoyancy pushes a submerged probe up; BoatManager persists velocity.
extends GdUnitTestSuite

func test_submerged_probe_gets_upward_force() -> void:
	# TODO: place a buoyancy body below the ocean plane, step physics,
	# assert net upward velocity.

func test_boat_manager_save_load_roundtrips_velocity() -> void:
	# v2->v3 save schema added boat velocity fields — confirm they survive.
```

### `tests/unit/data/test_data_resources.gd`

```gdscript
# Schema sanity for every authored .tres under data/.
extends GdUnitTestSuite

func test_all_item_defs_load_with_required_fields() -> void:
	for path in _tres_in("res://data/items/"):
		var res := load(path)
		assert_object(res).is_not_null()
		assert_str(String(res.id)).is_not_empty()

func test_skill_curves_are_monotonic() -> void:
	for path in _tres_in("res://data/skills/"):
		var def := load(path) as SkillDef
		var prev := -1.0
		for threshold in def.xp_curve:
			assert_float(threshold).is_greater(prev)
			prev = threshold

func test_island_def_ids_are_unique() -> void:
	# TODO: collect every IslandDef.id, assert no duplicates.

# func _tres_in(dir: String) -> PackedStringArray: ... DirAccess scan
```

**Phase 8 target: ~15 cases.**

## Phase 9 — Multiplayer scenarios

Builds on the Phase 4 two-peer harness (host + client headless processes).

### `tests/multiplayer/test_authority.gd`

```gdscript
# Authority is derived from the Player_<peer_id> node name.
func test_player_node_authority_matches_peer_id() -> void:
	# TODO: spawn Player_2, assert get_multiplayer_authority() == 2.
```

### `tests/multiplayer/test_damage_routing.gd`

```gdscript
# A non-authority caller routes damage via take_damage_rpc to the owner.
func test_remote_damage_routes_to_owner() -> void:
	# TODO: peer A calls take_damage on peer B's player; assert HP is applied
	# on B (the authority) and replicates back to A.
```

### `tests/multiplayer/test_spawn.gd`

```gdscript
# Host spawns one Player per peer on world load and on late-join.
func test_late_joiner_gets_spawned_on_ring() -> void:
	# TODO: connect a third peer mid-session, assert a Player_<id> appears
	# offset on the mainland anchor ring.
```

### `tests/multiplayer/test_world_save_ownership.gd`

```gdscript
# Regression: a returning client must not clobber the host's world save.
func test_ex_client_save_is_noop_after_disconnect() -> void:
	# TODO: client disconnects to lobby (OfflineMultiplayerPeer restored),
	# assert SaveSystem.save() writes nothing — guards commit 8578500.
```

**Phase 9 target: ~8 cases.**

## Rollout

| Phase | Area | Cases | Depends on |
|-------|------|-------|------------|
| 6 | Persistence & autoload state | ~20 | Phase 0–2 |
| 7 | Behavior, FSM, commands | ~22 | Phase 3 (integration scaffold) |
| 8 | World, generation, physics, data | ~15 | Phase 3 |
| 9 | Multiplayer scenarios | ~8 | Phase 4 (MP harness) |

Total: ~65 new cases, suite grows to ~90+.

## Verification

- Per suite while authoring: `pwsh tests/run_tests.ps1 <subpath>`.
- Full regression: `pwsh tests/run_tests.ps1` — exit 0, JUnit XML in
  `tests/.results/`.
- New golden snapshots (`zones_default`, etc.) are recorded on first run —
  review and commit the generated `tests/fixtures/golden/*.json`.
- After adding helper `class_name`s, refresh the class cache:
  `godot --headless --path . --import`.
