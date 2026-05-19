# Unit test — V3Codec (scripts/util/v3_codec.gd).
# Pure logic: Vector3 <-> Array serialization used by the save system.
extends GdUnitTestSuite


func test_encode_returns_xyz_array() -> void:
	assert_array(V3Codec.encode(Vector3(1.0, 2.0, 3.0))).is_equal([1.0, 2.0, 3.0])


func test_decode_rebuilds_vector() -> void:
	assert_vector(V3Codec.decode([1.0, 2.0, 3.0])).is_equal(Vector3(1.0, 2.0, 3.0))


func test_roundtrip_preserves_value() -> void:
	var v := Vector3(-12.5, 0.0, 99.25)
	assert_vector(V3Codec.decode(V3Codec.encode(v))).is_equal(v)


func test_decode_coerces_int_entries() -> void:
	# Save data parsed from JSON can yield ints; decode() must float-coerce.
	assert_vector(V3Codec.decode([1, 2, 3])).is_equal(Vector3(1.0, 2.0, 3.0))
