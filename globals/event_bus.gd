extends Node
# Project-wide signals. Systems emit/listen here instead of holding refs to each other.

signal item_picked_up(item_id: StringName, count: int)
signal enemy_killed(enemy_id: StringName, killer: Node)
signal skill_xp_gained(skill_id: StringName, amount: float)
signal skill_leveled(skill_id: StringName, new_level: int)
signal station_discovered(station_id: StringName)
signal boss_defeated(boss_id: StringName)
signal time_phase_changed(phase: int)
signal damage_dealt(attacker: Node, target: Node, weapon_id: StringName, skill_id: StringName, amount: float)
signal player_hp_changed(hp: float, max_hp: float)
signal player_stamina_changed(stamina: float, max_stamina: float)
signal player_died()
signal player_respawned()
signal player_parried(attacker: Node)
signal world_loaded
signal island_loaded(placement: IslandPlacement, instance: Node3D)
signal island_unloaded(runtime_id: StringName)
signal biome_entered(biome: BiomeDef)
