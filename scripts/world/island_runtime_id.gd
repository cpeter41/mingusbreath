class_name IslandRuntimeId

static func compute(world_seed: int, slot_index: int, def_id: StringName) -> StringName:
	return StringName("%d::%d::%s" % [world_seed, slot_index, String(def_id)])
