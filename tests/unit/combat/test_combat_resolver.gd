# Unit test — CombatResolver (scripts/combat/combat_resolver.gd).
# resolve() applies a +10% per skill-level damage multiplier. Skill levels are
# read from the SkillManager autoload; tests seed its `skills` dict directly
# and clear it after each test to keep cases isolated.
extends GdUnitTestSuite

const SKILL := &"test_blade"


func after_test() -> void:
	SkillManager.skills.clear()


func test_no_skill_id_returns_base_damage() -> void:
	# Empty skill id skips the level lookup entirely.
	assert_float(CombatResolver.resolve(null, null, &"sword", 10.0)).is_equal(10.0)


func test_level_1_multiplier_is_one() -> void:
	SkillManager.skills[SKILL] = {"level": 1, "xp": 0.0}
	assert_float(CombatResolver.resolve(null, null, &"sword", 10.0, SKILL)).is_equal(10.0)


func test_level_scales_damage_by_ten_percent_per_level() -> void:
	SkillManager.skills[SKILL] = {"level": 5, "xp": 0.0}
	# 10 * (1 + 0.1 * (5 - 1)) = 14.0
	assert_float(CombatResolver.resolve(null, null, &"sword", 10.0, SKILL)) \
		.is_equal_approx(14.0, 0.0001)


func test_unregistered_skill_defaults_to_level_1() -> void:
	# SkillManager.get_level() returns 1 for any unseen skill id.
	assert_float(CombatResolver.resolve(null, null, &"sword", 20.0, &"never_seen")) \
		.is_equal(20.0)
