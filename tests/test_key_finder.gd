extends TestCase


## A fake exe: the key's inner-pad block (key XOR 0x36, padded to 64 bytes) between filler bytes.
func _fake_exe(key: PackedByteArray) -> PackedByteArray:
	var block := key.duplicate()
	block.resize(64)
	for i in range(block.size()):
		block[i] ^= 0x36
	var filler := PackedByteArray()
	filler.resize(100)
	filler.fill(0x90)
	return filler + block + filler


func test_finds_key() -> void:
	var key := (KeyFinder.KEY_PREFIX + "-rest-of-key-1234567890").to_ascii_buffer()
	var result := KeyFinder.find_key(_fake_exe(key))
	assert_ok(result)
	assert_eq(result.value, key)


func test_key_ending_on_chunk_boundary() -> void:
	var key := (KeyFinder.KEY_PREFIX + "-ends-at-32!").to_ascii_buffer()
	assert_eq(key.size(), 32, "fixture")
	assert_eq(KeyFinder.find_key(_fake_exe(key)).value, key)


func test_skips_false_first_byte_matches() -> void:
	var key := (KeyFinder.KEY_PREFIX + "-xyz").to_ascii_buffer()
	var decoy := PackedByteArray([ord("a") ^ 0x36, 0, ord("a") ^ 0x36, ord("z") ^ 0x36])
	assert_eq(KeyFinder.find_key(decoy + _fake_exe(key)).value, key)


func test_missing_key_fails() -> void:
	var empty := PackedByteArray()
	empty.resize(1000)
	assert_failed(KeyFinder.find_key(empty))


func test_missing_file_fails() -> void:
	assert_failed(KeyFinder.find_key_in_file("res://does/not/exist.exe"))
