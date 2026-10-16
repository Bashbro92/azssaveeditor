extends TestCase


func _exe(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for part: Variant in parts:
		out.append_array(part.to_ascii_buffer() if part is String else PackedByteArray(part))
	return out


func test_version_right_before_anchor() -> void:
	assert_eq(VersionFinder.find_version(_exe(["junk n", "0.94.1", "A new version is out!"])), "0.94.1")


func test_skips_separator_bytes_and_dots() -> void:
	var exe := _exe(["discord.rs.", "0.84.3", [0], "update: up to date (site has v"])
	assert_eq(VersionFinder.find_version(exe), "0.84.3")


func test_shortest_candidate_wins() -> void:
	var exe := _exe(["level1", "2.3.4", "A new version is out!", "x", "2.3.4", [1], "update: up to date (site has v"])
	assert_eq(VersionFinder.find_version(exe), "2.3.4", "a digit before the version is another literal")


func test_no_version() -> void:
	assert_eq(VersionFinder.find_version(_exe(["nothing here"])), "")
	assert_eq(VersionFinder.find_version(_exe(["v1.2A new version is out!"])), "", "not major.minor.patch")


func test_byte_search() -> void:
	var hay := "abcabd".to_ascii_buffer()
	assert_eq(ByteSearch.find(hay, "abd".to_ascii_buffer()), 3)
	assert_eq(ByteSearch.find(hay, "abc".to_ascii_buffer(), 1), -1)
	assert_eq(ByteSearch.find(hay, "bdx".to_ascii_buffer()), -1, "runs past the end")
	assert_eq(ByteSearch.find(hay, PackedByteArray()), -1)
