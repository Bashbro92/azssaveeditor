extends TestCase
## Hash and table-decryption checks use published MPQ constants. Reading a real archive needs the game's
## Data folder: set AZS_DATA (those tests pass vacuously otherwise and say so).

const SMALL_ARCHIVE := "patch-2.MPQ"
const KNOWN_FILE := "Creature\\Chicken\\Chicken.m2"

var data_dir := OS.get_environment("AZS_DATA")


func test_table_key_hashes() -> void:
	assert_eq(MpqArchive.hash_string("(hash table)", 3), 0xC3AF3770)
	assert_eq(MpqArchive.hash_string("(block table)", 3), 0xEC83B3A3)


func test_hash_is_case_insensitive() -> void:
	assert_eq(MpqArchive.hash_string("interface\\icons\\x.blp", 1), MpqArchive.hash_string("Interface\\Icons\\X.BLP", 1))


func test_decrypt_is_deterministic_and_changes_data() -> void:
	var plain := PackedByteArray(range(32))
	var once := MpqArchive.decrypt_block(plain, 0x12345678)
	assert_true(once != plain)
	assert_eq(MpqArchive.decrypt_block(plain, 0x12345678), once)


func test_open_missing_file_fails() -> void:
	assert_failed(MpqArchive.open("res://does/not/exist.MPQ"))


func test_open_non_mpq_fails() -> void:
	assert_failed(MpqArchive.open("res://project.godot"))


func test_real_archive_lists_and_reads() -> void:
	if data_dir.is_empty():
		print("  (test_real_archive_lists_and_reads: set AZS_DATA to run)")
		return
	var opened := MpqArchive.open(data_dir.path_join(SMALL_ARCHIVE))
	assert_ok(opened)
	var archive: MpqArchive = opened.value
	var names := archive.list_files()
	assert_true(names.size() > 100, "listfile has %d names" % names.size())
	assert_true(archive.has_file(KNOWN_FILE))
	var file := archive.read_file(KNOWN_FILE)
	assert_ok(file)
	assert_eq(file.value.slice(0, 4).get_string_from_ascii(), "MD20")
	assert_failed(archive.read_file("No\\Such\\File.blp"))


func test_real_icon_decodes() -> void:
	if data_dir.is_empty():
		return
	var archive: MpqArchive = MpqArchive.open(data_dir.path_join("patch.MPQ")).value
	var file := archive.read_file("Interface\\Icons\\Ability_Warrior_Cleave.blp")
	assert_ok(file)
	var image := BlpImage.decode(file.value)
	assert_ok(image)
	assert_eq(image.value.get_size(), Vector2i(64, 64))
