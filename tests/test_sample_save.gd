extends TestCase
## End-to-end checks against a real save and the real key. Needs the game executable (Windows or
## Linux build): set AZS_EXE.

const FIXTURE := "res://tests/fixtures/sample.sav"

var key: PackedByteArray
var version: String
var game: GameData
var sealed: String


func before_all() -> void:
	var exe := OS.get_environment("AZS_EXE")
	if exe.is_empty():
		skip("set AZS_EXE to the game exe to run")
		return
	var bytes := KeyFinder.read_exe(exe)
	var image := ExeImage.open(bytes.value) if bytes.ok else bytes
	var found := KeyFinder.find_key(bytes.value, image.value) if image.ok else image
	if not found.ok:
		skip(found.error)
		return
	key = found.value
	version = VersionFinder.find_version(bytes.value)
	game = GameData.from_exe(image.value).value
	sealed = FileAccess.get_file_as_string(FIXTURE)


func test_key_length() -> void:
	assert_eq(key.size(), 42)


func test_game_version_found() -> void:
	assert_true(version.split(".").size() == 3, "got '%s'" % version)


func test_sample_decrypts() -> void:
	var result := SaveCodec.unseal(key, sealed)
	assert_ok(result)
	assert_true(result.value.begins_with("pick|1|1|1|duskwood|Broisar|"))


func test_sample_reseals_byte_for_byte() -> void:
	var plain: String = SaveCodec.unseal(key, sealed).value
	var header := Marshalls.base64_to_raw(sealed.strip_edges().substr(SaveCodec.MAGIC.length())).slice(0, 16)
	assert_eq(SaveCodec.seal(key, plain, header).value, sealed.strip_edges())


## Same totals as the generated "100%" save that was verified in game (2026-10-15), except that
## achievements now cover all 66 keys found in the exe (the verified save had 39 of them), and
## game 0.94.1 added the druid spell Shred and with it one legendary codex entry (140 -> 141).
func test_fill_all_matches_verified_save() -> void:
	var p := SaveProgress.from_text(SaveCodec.unseal(key, sealed).value)
	p.fill_all(game, 0)
	var doc := SaveDoc.parse(p.to_text())
	assert_eq(p.item_count(), 415, "items")
	assert_eq(doc.first("seen")[1].split(",").size(), 141, "codex entries")
	assert_eq(p.achievements().size(), 66, "achievements")
	assert_eq(doc.records_of("beat").size(), 81, "zone wins")
	assert_eq(p.hero_classes().size(), 9, "heroes")


func test_sample_parses_and_round_trips() -> void:
	var plain: String = SaveCodec.unseal(key, sealed).value
	var doc := SaveDoc.parse(plain)
	assert_eq(doc.to_text(), plain)
	assert_eq(doc.records_of("hero").size(), 7)
	assert_eq(doc.first("stat")[1], "kills=10945,gold=7764,guardians=1,bosses=15,runs=5,wins=1,caches=49")
