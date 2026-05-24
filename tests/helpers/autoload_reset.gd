class_name AutoloadReset
## Static helpers to clear autoload state between tests.
##
## Autoloads are singletons that live for the whole test run, so any test that
## mutates one must reset it — otherwise the next test inherits the change.
## Call the relevant reset in `before_test()` / `after_test()`.


## Resets every autoload this helper knows how to reset.
static func reset_all() -> void:
	reset_game_state()
	reset_skills()
	reset_zones()


static func reset_game_state() -> void:
	GameState.world_seed = 0
	GameState.paused = false
	GameState.last_played_at = 0


static func reset_skills() -> void:
	SkillManager.skills.clear()


static func reset_zones() -> void:
	ZoneMap.zones.clear()
