extends TestCase

var key := "test-key-not-the-real-one".to_ascii_buffer()


func _round_trip(plain: String) -> String:
	return SaveCodec.unseal(key, SaveCodec.seal(key, plain).value).value


func test_round_trip() -> void:
	var plain := "pick|1|1|1|duskwood|Broisar|4,5,2,4,0|100,100,100,100\nstat|kills=1\n"
	assert_eq(_round_trip(plain), plain)


func test_round_trip_around_block_size() -> void:
	for n in [0, 1, 19, 20, 21, 40, 1000]:
		var plain := "x".repeat(n)
		assert_eq(_round_trip(plain), plain, "length %d" % n)


func test_round_trip_utf8() -> void:
	assert_eq(_round_trip("hero|Brøisar|Ünïcødé"), "hero|Brøisar|Ünïcødé")


func test_seal_starts_with_magic() -> void:
	assert_true(SaveCodec.seal(key, "abc").value.begins_with(SaveCodec.MAGIC))


func test_fixed_header_is_deterministic() -> void:
	var header := PackedByteArray(range(16))
	assert_eq(SaveCodec.seal(key, "abc", header).value, SaveCodec.seal(key, "abc", header).value)


func test_fresh_header_each_seal() -> void:
	assert_true(SaveCodec.seal(key, "abc").value != SaveCodec.seal(key, "abc").value)


func test_seal_rejects_bad_header_size() -> void:
	assert_failed(SaveCodec.seal(key, "abc", PackedByteArray([1, 2, 3])))


func test_tampered_save_is_rejected() -> void:
	var sealed: String = SaveCodec.seal(key, "stat|gold=100").value
	var raw := Marshalls.base64_to_raw(sealed.substr(SaveCodec.MAGIC.length()))
	raw[20] ^= 1
	assert_failed(SaveCodec.unseal(key, SaveCodec.MAGIC + Marshalls.raw_to_base64(raw)))


func test_wrong_key_is_rejected() -> void:
	var sealed: String = SaveCodec.seal(key, "abc").value
	assert_failed(SaveCodec.unseal("other".to_ascii_buffer(), sealed))


func test_bad_input_is_rejected() -> void:
	var short := SaveCodec.MAGIC + Marshalls.raw_to_base64("short".to_ascii_buffer())
	for text in ["", "hello", "RSE1:", "RSE1:!!!!", "RSE1:abc", short]:
		assert_failed(SaveCodec.unseal(key, text), "input %s" % text)


func test_surrounding_whitespace_is_ignored() -> void:
	var sealed: String = SaveCodec.seal(key, "abc").value
	assert_eq(SaveCodec.unseal(key, "  " + sealed + "\n").value, "abc")
