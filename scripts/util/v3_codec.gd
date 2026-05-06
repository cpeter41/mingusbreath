class_name V3Codec

static func encode(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func decode(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
