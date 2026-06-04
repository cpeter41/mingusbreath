# Unit test — StateMachine (scripts/shared/state_machine.gd).
# Transition rules: exit-then-enter, ignore unknown target, ignore re-entry.
extends GdUnitTestSuite


# Spy state — counts lifecycle calls. Concrete game states omit class_name and
# are keyed by node name, so a BaseState subclass stands in fine here.
class SpyState extends BaseState:
	var entered := 0
	var exited := 0
	var ticked := 0

	func enter() -> void:
		entered += 1

	func exit() -> void:
		exited += 1

	func physics_update(_delta: float) -> void:
		ticked += 1


func _spy(state_name: String) -> SpyState:
	var s: SpyState = auto_free(SpyState.new())
	s.name = state_name
	return s


func _machine(states: Dictionary) -> StateMachine:
	var sm: StateMachine = auto_free(StateMachine.new())
	sm._states = states  # test seam — states are normally registered from children
	return sm


func test_first_transition_enters_state() -> void:
	var a := _spy("A")
	var sm := _machine({"a": a})
	sm.transition_to("a")
	assert_int(a.entered).is_equal(1)
	assert_str(sm.current_state_name()).is_equal("a")


func test_transition_runs_exit_then_enter() -> void:
	var a := _spy("A")
	var b := _spy("B")
	var sm := _machine({"a": a, "b": b})
	sm.transition_to("a")
	sm.transition_to("b")
	assert_int(a.exited).is_equal(1)
	assert_int(b.entered).is_equal(1)
	assert_str(sm.current_state_name()).is_equal("b")


func test_unknown_state_is_noop() -> void:
	var a := _spy("A")
	var sm := _machine({"a": a})
	sm.transition_to("a")
	sm.transition_to("does_not_exist")
	assert_str(sm.current_state_name()).is_equal("a")
	assert_int(a.exited).is_equal(0)


func test_reentry_to_current_state_is_noop() -> void:
	var a := _spy("A")
	var sm := _machine({"a": a})
	sm.transition_to("a")
	sm.transition_to("a")
	assert_int(a.entered).is_equal(1)
	assert_int(a.exited).is_equal(0)


func test_current_state_name_is_empty_before_first_transition() -> void:
	assert_str(_machine({}).current_state_name()).is_equal("")


func test_physics_update_forwards_only_to_current_state() -> void:
	var a := _spy("A")
	var b := _spy("B")
	var sm := _machine({"a": a, "b": b})
	sm.transition_to("a")
	sm.physics_update(0.016)
	sm.physics_update(0.016)
	assert_int(a.ticked).is_equal(2)
	assert_int(b.ticked).is_equal(0)
