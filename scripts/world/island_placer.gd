class_name IslandPlacer

const ISLAND_SPACING_BUFFER_M := 80.0
const MAINLAND_DEF_ID := &"island_mainland_01"

## Deterministic rejection-sampling placement.
## Slot 0 = mainland, pinned to top-right corner (+X, -Z).
## Next slots fill a guaranteed `min_per_def` copies of every non-mainland def.
## Remaining slots pick defs by weight. All slots draw random positions while
## avoiding overlaps and respecting zone difficulty when possible.
static func place(
		defs: Array,
		world_seed: int,
		world_size_m: float,
		island_count: int,
		max_attempts: int = 64,
		min_per_def: int = 0) -> Array:

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

	# Build the per-slot def queue: guaranteed slots first (min_per_def copies of
	# every non-mainland def, sorted by id for determinism), then null entries
	# for weighted-random fill.
	var spawnable: Array = []
	for d in defs:
		var def := d as IslandDef
		if def.id == MAINLAND_DEF_ID:
			continue
		if def.placement_weight <= 0.0:
			continue
		spawnable.append(def)
	spawnable.sort_custom(func(a, b): return String(a.id) < String(b.id))

	var slot_defs: Array = []  # one per non-mainland slot; null = weighted pick
	for def in spawnable:
		for _i in min_per_def:
			slot_defs.append(def)
	var guaranteed := slot_defs.size()
	var remaining: int = max(0, (island_count - 1) - guaranteed)
	for _i in remaining:
		slot_defs.append(null)
	if guaranteed > island_count - 1:
		push_warning("IslandPlacer: %d guaranteed slots exceed island_count-1=%d; some defs may be short" % [guaranteed, island_count - 1])

	for slot in range(1, island_count):
		var queue_index := slot - 1
		if queue_index >= slot_defs.size():
			break

		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed ^ 0xA1B2C3 ^ slot

		var chosen_def: IslandDef = slot_defs[queue_index]
		if chosen_def == null:
			chosen_def = _pick_weighted(defs, rng)
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
