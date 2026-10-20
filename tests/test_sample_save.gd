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
## achievements now cover all 73 keys found in the exe (the verified save had 39 of them), game 0.94.1
## added the druid spell Shred and with it one legendary codex entry (140 -> 141), and 0.96.0 three zones
## and the PvP tier (415 -> 498 pieces), with zones opened by `open|` lines in place of `unlock|`. 0.104.0's warlock
## spell Demonic Empowerment adds its legendary codex entry (142).
func test_fill_all_matches_verified_save() -> void:
	var p := _read(SaveCodec.unseal(key, sealed).value)
	p.fill_all(game, 0)
	var text := p.to_text()
	assert_eq(p.item_count(), 498, "items")
	var parts := version.split(".")
	var codex := 142 if parts.size() == 3 and parts[1].to_int() >= 104 else 141
	assert_eq(_lines(text, "seen")[0][1].split(",").size(), codex, "codex entries")
	assert_eq(p.achievements().size(), 73, "achievements")
	var wins := 0
	for r in _lines(text, "beat"):
		wins += r[2].split(",").size()
	assert_eq(wins, 108, "zone wins")
	assert_eq(_lines(text, "beat").size(), 9, "one beat line a class")
	assert_eq(_lines(text, "unlock").size(), 0, "the older lines are gone")
	for r in _lines(text, "open"):
		assert_eq(r[2], "naxx", "every zone open")
	assert_eq(_lines(text, "open").size(), 9)
	assert_eq(p.hero_classes().size(), 9, "heroes")


func test_sample_parses() -> void:
	var p := _read(SaveCodec.unseal(key, sealed).value)
	assert_eq(p.hero_classes().size(), 7)
	assert_eq(p.stat("kills"), 10945)
	assert_eq(p.stat("caches"), 49)


## The sample (written by 0.94.1) comes out as the game rewrites it: no unlock lines, the game's line order, and
## reading that back changes nothing.
func test_sample_comes_out_as_the_game_writes_it() -> void:
	var text := _read(SaveCodec.unseal(key, sealed).value).to_text()
	assert_eq(_lines(text, "unlock").size(), 0)
	assert_eq(_lines(text, "stat")[0][1], "kills=10945,gold=7764,guardians=1,bosses=15,runs=5,wins=1,caches=49")
	var kinds := PackedStringArray()
	for line in text.split("\n", false):
		if not kinds.has(line.get_slice("|", 0)):
			kinds.append(line.get_slice("|", 0))
	var order := ["pick", "open", "items", "equip", "look", "talent", "spec", "seen", "ach", "achat", "stat", "beat",
			"perk", "tabard", "pets", "resets", "hero"]
	var last := -1
	for kind in kinds:
		assert_true(order.find(kind) > last, "%s in the writer's order: %s" % [kind, kinds])
		last = order.find(kind)
	var again := _read(text)
	assert_false(again.is_modified())
	assert_eq(again.to_text(), text)


## A save the game wrote (0.100.1 on) writes back byte for byte. Set AZS_GAME_SAVE to a copy of one (an exported
## .sav or the game's characters.txt); never point it at the game's own file.
func test_a_game_save_writes_back_byte_for_byte() -> void:
	var path := OS.get_environment("AZS_GAME_SAVE")
	if path.is_empty():
		return
	var plain := SaveCodec.unseal(key, FileAccess.get_file_as_string(path))
	assert_ok(plain)
	if plain.ok:
		var p := _read(plain.value)
		assert_eq(p.to_text(), plain.value)
		assert_false(p.is_modified())


func _read(text: String) -> SaveProgress:
	var zones: Array[String] = []
	zones.assign(game.zone_ids())
	var p := SaveProgress.from_text(text, zones)
	p.relearn_talents(func(c: int) -> Array:
		var hero_class := game.class_by_wow_id(c)
		return [] if hero_class.is_empty() else game.trees_for_class(hero_class["id"]))
	return p


static func _lines(text: String, kind: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for line in text.split("\n", false):
		if line.begins_with(kind + "|"):
			out.append(line.split("|"))
	return out
