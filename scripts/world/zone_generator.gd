class_name ZoneGenerator

const ZONES_DIR := "res://data/zones/"
const EASY_DEF_PATH := ZONES_DIR + "zone_easy.tres"
const MEDIUM_DEF_PATH := ZONES_DIR + "zone_medium.tres"
const HARD_DEF_PATH := ZONES_DIR + "zone_hard.tres"

const STARTER_INSET := 200.0

const EASY_PRIMARY_RADIUS := 3000.0
const EASY_SUPP_MIN := 1
const EASY_SUPP_MAX := 2
const EASY_SUPP_OFFSET_MAX := 1500.0
const EASY_SUPP_R_MIN := 1200.0
const EASY_SUPP_R_MAX := 1800.0

const HARD_ANCHOR_MIN := 2
const HARD_ANCHOR_MAX := 4
const HARD_R_MIN := 1200.0
const HARD_R_MAX := 1800.0
const HARD_K := 2.5

const MED_ANCHOR_MIN := 2
const MED_ANCHOR_MAX := 4
const MED_R_MIN := 1300.0
const MED_R_MAX := 1700.0

const ANCHOR_MIN_SEP := 800.0
const MAX_SAMPLE_ATTEMPTS := 256


static func generate(world_seed: int, world_size_m: float) -> Array:
	var zones: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x205E5E5E

	var half := world_size_m * 0.5
	var starter := Vector3(half - STARTER_INSET, 0.0, -(half - STARTER_INSET))
	var max_dist := starter.distance_to(Vector3(-half, 0.0, half))

	var lo := -half
	var hi := half

	var easy := _build_easy(rng, starter)
	zones.append(easy)

	var hard := _build_hard(rng, starter, max_dist, lo, hi, _collect_anchors(zones))
	zones.append(hard)

	var medium := _build_medium(rng, starter, max_dist, lo, hi, _collect_anchors(zones))
	zones.append(medium)

	_sanity_check(zones)
	return zones


static func _build_easy(rng: RandomNumberGenerator, starter: Vector3) -> ZoneInstance:
	var z := ZoneInstance.new()
	z.def = _load_or_fallback(EASY_DEF_PATH, Difficulty.EASY, Color(0.25, 0.85, 0.35, 1.0))
	z.anchors.append(starter)
	z.radii.append(EASY_PRIMARY_RADIUS)

	var supp := rng.randi_range(EASY_SUPP_MIN, EASY_SUPP_MAX)
	# Push supplementary anchors toward world center (away from corner).
	var to_center := (Vector3.ZERO - starter).normalized()
	for i in supp:
		var dist := rng.randf_range(600.0, EASY_SUPP_OFFSET_MAX)
		# Cone around to_center, ±60deg.
		var ang := rng.randf_range(-PI / 3.0, PI / 3.0)
		var dir := to_center.rotated(Vector3.UP, ang)
		var p := starter + dir * dist
		z.anchors.append(Vector3(p.x, 0.0, p.z))
		z.radii.append(rng.randf_range(EASY_SUPP_R_MIN, EASY_SUPP_R_MAX))
	return z


static func _build_hard(
		rng: RandomNumberGenerator,
		starter: Vector3,
		max_dist: float,
		lo: float,
		hi: float,
		existing: Array) -> ZoneInstance:
	var z := ZoneInstance.new()
	z.def = _load_or_fallback(HARD_DEF_PATH, Difficulty.HARD, Color(0.9, 0.2, 0.2, 1.0))
	var target := rng.randi_range(HARD_ANCHOR_MIN, HARD_ANCHOR_MAX)
	var own_anchors: Array = []

	for _i in target:
		var placed_anchor := false
		for _a in MAX_SAMPLE_ATTEMPTS:
			var cx := rng.randf_range(lo, hi)
			var cz := rng.randf_range(lo, hi)
			var p := Vector3(cx, 0.0, cz)
			var dist_norm: float = clamp(p.distance_to(starter) / max_dist, 0.0, 1.0)
			var accept_prob: float = pow(dist_norm, HARD_K)
			if rng.randf() > accept_prob:
				continue
			if _too_close_to_any(p, existing, ANCHOR_MIN_SEP):
				continue
			if _too_close_to_any(p, own_anchors, ANCHOR_MIN_SEP):
				continue
			z.anchors.append(p)
			z.radii.append(rng.randf_range(HARD_R_MIN, HARD_R_MAX))
			own_anchors.append(p)
			placed_anchor = true
			break
		if not placed_anchor:
			push_warning("ZoneGenerator: hard anchor placement gave up after %d attempts" % MAX_SAMPLE_ATTEMPTS)
	return z


static func _build_medium(
		rng: RandomNumberGenerator,
		starter: Vector3,
		max_dist: float,
		lo: float,
		hi: float,
		existing: Array) -> ZoneInstance:
	var z := ZoneInstance.new()
	z.def = _load_or_fallback(MEDIUM_DEF_PATH, Difficulty.MEDIUM, Color(0.95, 0.85, 0.2, 1.0))
	var target := rng.randi_range(MED_ANCHOR_MIN, MED_ANCHOR_MAX)
	var own_anchors: Array = []

	for _i in target:
		var placed_anchor := false
		for _a in MAX_SAMPLE_ATTEMPTS:
			var cx := rng.randf_range(lo, hi)
			var cz := rng.randf_range(lo, hi)
			var p := Vector3(cx, 0.0, cz)
			var dist_norm: float = clamp(p.distance_to(starter) / max_dist, 0.0, 1.0)
			# Tent peaked at 0.5.
			var accept_prob: float = 1.0 - 2.0 * abs(dist_norm - 0.5)
			if rng.randf() > accept_prob:
				continue
			if _too_close_to_any(p, existing, ANCHOR_MIN_SEP):
				continue
			if _too_close_to_any(p, own_anchors, ANCHOR_MIN_SEP):
				continue
			z.anchors.append(p)
			z.radii.append(rng.randf_range(MED_R_MIN, MED_R_MAX))
			own_anchors.append(p)
			placed_anchor = true
			break
		if not placed_anchor:
			push_warning("ZoneGenerator: medium anchor placement gave up after %d attempts" % MAX_SAMPLE_ATTEMPTS)
	return z


static func _collect_anchors(zones: Array) -> Array:
	var out: Array = []
	for z in zones:
		for a in (z as ZoneInstance).anchors:
			out.append(a)
	return out


static func _too_close_to_any(p: Vector3, points: Array, min_sep: float) -> bool:
	for q in points:
		if p.distance_to(q) < min_sep:
			return true
	return false


static func _load_or_fallback(path: String, difficulty: int, color: Color) -> ZoneDef:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is ZoneDef:
			return res as ZoneDef
	var d := ZoneDef.new()
	d.difficulty = difficulty
	d.debug_color = color
	return d


static func _sanity_check(zones: Array) -> void:
	for z in zones:
		var zi := z as ZoneInstance
		for i in zi.anchors.size():
			var p: Vector3 = zi.anchors[i]
			var best: ZoneInstance = null
			var best_f := -INF
			for other in zones:
				var f := (other as ZoneInstance).field_at(p)
				if f > best_f:
					best_f = f
					best = other
			if best != zi:
				push_warning("ZoneGenerator: anchor %s of zone diff=%d classifies to diff=%d" % [p, zi.def.difficulty, best.def.difficulty])
