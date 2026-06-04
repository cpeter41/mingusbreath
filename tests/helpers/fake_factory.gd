class_name FakeFactory
## Builds lightweight stub nodes so unit tests stay scene-free and fast.
## Returned nodes are plain `Node`s — register them with `auto_free()` (or
## `add_child_autofree()`) in the test so GdUnit4 cleans them up.


static func make_combatant(hp: float = 100.0) -> FakeCombatant:
	var c := FakeCombatant.new()
	c.hp = hp
	c.max_hp = hp
	return c
