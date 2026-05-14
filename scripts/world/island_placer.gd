class_name IslandPlacer

const ISLAND_SPACING_BUFFER_M := 80.0
const MAINLAND_DEF_ID := &"island_mainland_01"

## Deterministic rejection-sampling placement.
## Slot 0 = mainland, pinned to top-right corner (+X, -Z).
## Slots 1..N pick defs by weight then draw random positions, avoiding mainland and borders.
static func place(
		defs: Array,
		world_seed: int,
		world_size_m: float,
		island_count: int,
		max_attempts: int = 64) -> Array:

	var placements: Array = []

	# Find mainland def.
	var mainland_def: IslandDef = null
	for d in defs:
		if d.id == MAINLAND_DEF_ID:
			mainland_def = d
			break
	if mainland_def == null:
		push_error("IslandPlacer: no IslandDef with id '%s' found in defs" % MAINLAND_DEF_ID)
		return placements

	var half := world_size_m * 0.5

	# Slot 0 — mainland pinned to top-right corner.
	var mainland_inset := mainland_def.footprint_radius + ISLAND_SPACING_BUFFER_M
	var mainland := IslandPlacement.new()
	mainland.def = mainland_def
	mainland.position = Vector3(half - mainland_inset, 0.0, -(half - mainland_inset))
	mainland.rotation_y = 0.0
	mainland.slot_index = 0
	mainland.runtime_id = IslandRuntimeId.compute(world_seed, 0, mainland_def.id)
	placements.append(mainland)

	for slot in range(1, island_count):
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed ^ 0xA1B2C3 ^ slot

		# Weighted pick of def for this slot. Mainland is excluded by weight=0.
		var chosen_def := _pick_weighted(defs, rng)
		if chosen_def == null:
			push_warning("IslandPlacer: slot %d — no defs available, skipping" % slot)
			continue

		# Keep islands well clear of the world border walls.
		var edge_inset := chosen_def.footprint_radius + ISLAND_SPACING_BUFFER_M
		var lo := -half + edge_inset
		var hi :=  half - edge_inset

		# Two-pass rejection sampling. Pass 1 honors zone-difficulty match;
		# pass 2 drops the zone constraint and warns.
		var placed := _try_place_slot(
				placements, chosen_def, slot, rng, world_seed,
				lo, hi, max_attempts, true)
		if not placed:
			placed = _try_place_slot(
					placements, chosen_def, slot, rng, world_seed,
					lo, hi, max_attempts, false)
			if placed:
				push_warning("IslandPlacer: slot %d — zone-match fallback (could not find matching zone)" % slot)

		if not placed:
			push_warning("IslandPlacer: slot %d — could not place after %d attempts, skipping" % [slot, max_attempts * 2])

	return placements


static func _try_place_slot(
		placements: Array,
		chosen_def: IslandDef,
		slot: int,
		rng: RandomNumberGenerator,
		world_seed: int,
		lo: float,
		hi: float,
		max_attempts: int,
		enforce_zone: bool) -> bool:
	for _attempt in range(max_attempts):
		var cx := rng.randf_range(lo, hi)
		var cz := rng.randf_range(lo, hi)
		var candidate := Vector3(cx, 0.0, cz)

		if _too_close(candidate, chosen_def.footprint_radius, placements):
			continue
		if enforce_zone and ZoneMap.classify(candidate) != chosen_def.difficulty:
			continue

		var p := IslandPlacement.new()
		p.def = chosen_def
		p.position = candidate
		p.rotation_y = rng.randf_range(0.0, TAU)
		p.slot_index = slot
		p.runtime_id = IslandRuntimeId.compute(world_seed, slot, chosen_def.id)
		placements.append(p)
		return true
	return false


static func _pick_weighted(defs: Array, rng: RandomNumberGenerator) -> IslandDef:
	var total: float = 0.0
	for d in defs:
		total += (d as IslandDef).placement_weight
	if total <= 0.0:
		return null
	var roll: float = rng.randf_range(0.0, total)
	var acc: float = 0.0
	for d in defs:
		var w: float = (d as IslandDef).placement_weight
		if w <= 0.0:
			continue
		acc += w
		if roll <= acc:
			return d as IslandDef
	return null


static func _too_close(candidate: Vector3, radius: float, placements: Array) -> bool:
	for p in placements:
		var min_dist: float = (p as IslandPlacement).def.footprint_radius + radius + ISLAND_SPACING_BUFFER_M
		if candidate.distance_to((p as IslandPlacement).position) < min_dist:
			return true
	return false
