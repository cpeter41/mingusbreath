class_name ZoneInstance
extends RefCounted

var def: ZoneDef
var anchors: PackedVector3Array = PackedVector3Array()
var radii: PackedFloat32Array = PackedFloat32Array()

func field_at(p: Vector3) -> float:
	var s := 0.0
	for i in anchors.size():
		var dx := p.x - anchors[i].x
		var dz := p.z - anchors[i].z
		var r := radii[i]
		s += exp(-(dx * dx + dz * dz) / (r * r))
	return s
