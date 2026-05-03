class_name IslandPlacer

const ISLAND_SPACING_BUFFER_M := 80.0
const STARTER_DEF_ID := &"island_meadows_01"

## Deterministic rejection-sampling placement.
## Slot 0 = starter island, always pinned to world origin.
## Slots 1..N pick defs by weight then draw random positions.
static func place(
		defs: Array,
		world_seed: int,
		world_size_m: float,
		island_count: int,
		max_attempts: int = 64) -> Array:

	var placements: Array = []

	# Find starter def.
	var starter_def: IslandDef = null
	for d in defs:
		if d.id == STARTER_DEF_ID:
			starter_def = d
			break
	if starter_def == null:
		push_error("IslandPlacer: no IslandDef with id '%s' found in defs" % STARTER_DEF_ID)
		return placements

	# Slot 0 — starter pinned to origin.
	var starter := IslandPlacement.new()
	starter.def = starter_def
	starter.position = Vector3.ZERO
	starter.rotation_y = 0.0
	starter.slot_index = 0
	starter.runtime_id = IslandRuntimeId.compute(world_seed, 0, starter_def.id)
	placements.append(starter)

	var half := world_size_m * 0.5

	for slot in range(1, island_count):
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed ^ 0xA1B2C3 ^ slot

		# Weighted pick of def for this slot.
		var chosen_def := _pick_weighted(defs, rng)
		if chosen_def == null:
			push_warning("IslandPlacer: slot %d — no defs available, skipping" % slot)
			continue

		# Rejection sampling for position.
		var placed := false
		for _attempt in range(max_attempts):
			var cx := rng.randf_range(-half, half)
			var cz := rng.randf_range(-half, half)
			var candidate := Vector3(cx, 0.0, cz)

			if _too_close(candidate, chosen_def.footprint_radius, placements):
				continue

			var p := IslandPlacement.new()
			p.def = chosen_def
			p.position = candidate
			p.rotation_y = rng.randf_range(0.0, TAU)
			p.slot_index = slot
			p.runtime_id = IslandRuntimeId.compute(world_seed, slot, chosen_def.id)
			placements.append(p)
			placed = true
			break

		if not placed:
			push_warning("IslandPlacer: slot %d — could not place after %d attempts, skipping" % [slot, max_attempts])

	return placements


static func _pick_weighted(defs: Array, rng: RandomNumberGenerator) -> IslandDef:
	var total: float = 0.0
	for d in defs:
		total += (d as IslandDef).placement_weight
	if total <= 0.0:
		return null
	var roll: float = rng.randf_range(0.0, total)
	var acc: float = 0.0
	for d in defs:
		acc += (d as IslandDef).placement_weight
		if roll <= acc:
			return d as IslandDef
	return defs[-1] as IslandDef


static func _too_close(candidate: Vector3, radius: float, placements: Array) -> bool:
	for p in placements:
		var min_dist: float = (p as IslandPlacement).def.footprint_radius + radius + ISLAND_SPACING_BUFFER_M
		if candidate.distance_to((p as IslandPlacement).position) < min_dist:
			return true
	return false
