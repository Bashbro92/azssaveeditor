extends TestCase
## The extractor's pure helpers and ExeImage on a tiny synthetic exe. The real exe is covered by
## test_real_game_data.gd.

const BLOCK: Array[String] = ["Fully Talented", "Collector", "Thrifty", "Win a run without buying a cache.",
		"Exterminator", "Slay 10,000 enemies.", "Scourge", "Slay 100,000 enemies.",
		"Earn all {n} talent points with one class."]

const BASE := 0x140000000
const RDATA_VA := 0x1000
const RDATA_OFFSET := 0x200


func _parse(run: String) -> Dictionary:
	var out := {}
	for a: Dictionary in GameDataExtractor.parse_achievement_run(run, BLOCK):
		out[a["name"]] = a
	return out


func test_splits_name_description_key_icon() -> void:
	var got := _parse("ThriftyWin a run without buying a cache.feat:thriftyINV_Box_01")
	assert_eq(got["Thrifty"], {"name": "Thrifty", "description": "Win a run without buying a cache.",
			"key": "feat:thrifty", "icon": "INV_Box_01", "group": "Feats"})


func test_icon_followed_directly_by_next_name() -> void:
	var got := _parse("ExterminatorSlay 10,000 enemies.count:kills10kINV_Sword_04ThriftyWin a run without "
			+ "buying a cache.feat:thriftyINV_Box_01")
	assert_eq(got["Exterminator"]["icon"], "INV_Sword_04")
	assert_eq(got["Thrifty"]["icon"], "INV_Box_01")


func test_missing_icon_reuses_previous() -> void:
	var got := _parse("ExterminatorSlay 10,000 enemies.count:kills10kINV_Sword_04ScourgeSlay 100,000 "
			+ "enemies.count:kills100k")
	assert_eq(got["Scourge"]["icon"], "INV_Sword_04")
	assert_eq(got["Scourge"]["key"], "count:kills100k")


func test_code_built_keys_and_templates() -> void:
	var got := _parse("Fully TalentedEarn all {n} talent points with one class." + GameDataExtractor.GAP
			+ "INV_Misc_Book_11CollectorINV_Chest_Chain")
	assert_eq(got["Fully Talented"]["key"], "talents:1")
	assert_eq(got["Fully Talented"]["description"], "Earn all 51 talent points with one class.")
	assert_eq(got["Fully Talented"]["icon"], "INV_Misc_Book_11")
	assert_eq(got["Collector"]["key"], "pieces:25")
	assert_eq(got["Collector"]["description"], "Collect 25 pieces of gear, of any class.")
	assert_eq(got["Collector"]["group"], "Collection")


func test_literal_run_collapses_binary_gaps() -> void:
	var raw := "ab".to_ascii_buffer() + PackedByteArray([0, 0xFF, 7]) + "c".to_ascii_buffer()
	assert_eq(GameDataExtractor.literal_run(raw), "ab" + GameDataExtractor.GAP + "c")


func test_templated_achievements() -> void:
	var classes := [{"id": "druid", "name": "Druid", "icon": "Icon_Druid"}]
	var zones := [{"id": "aq", "name": "Ahn'Qiraj", "bosses": [{"name": "Skeram", "final": false},
			{"name": "C'Thun", "final": true}]}]
	var got := GameDataExtractor.templated_achievements(classes, zones)
	assert_eq(got.map(func(a: Dictionary) -> String: return a["key"]),
			["class:druid", "classlast:druid", "zone:aq", "zone9:aq"])
	assert_eq(got[1]["description"], "Defeat C'Thun at Ahn'Qiraj with a Druid.")
	assert_eq(got[3]["name"], "Champion of Ahn'Qiraj")
	assert_eq(got[3]["group"], "Zones")


func test_links_exclusive_talents_both_ways() -> void:
	var tree := GameDataExtractor.link_exclusions([
		{"id": "bear", "name": "Dire Bear Form", "description": "Capstone. You can't also learn Cat Form."},
		{"id": "cat", "name": "Cat Form", "description": "Capstone. You can't also learn Dire Bear Form."},
		{"id": "hide", "name": "Thick Hide", "description": ""},
		{"id": "odd", "name": "Odd", "description": "You can't also learn Missing."},
	])
	assert_eq(tree.map(func(t: Dictionary) -> Array: return t["excludes"]), [["cat"], ["bear"], [], []])


## A minimal PE32+ image: headers, then one .rdata section at RDATA_OFFSET holding "Elwynn"
## followed by a `&str` (pointer, length) to it.
func _fake_exe() -> PackedByteArray:
	var exe := PackedByteArray()
	exe.resize(RDATA_OFFSET + 0x40)
	exe.encode_u16(0, 0x5A4D)              # "MZ"
	exe.encode_u32(0x3C, 0x40)             # PE header offset
	exe.encode_u32(0x40, 0x4550)           # "PE\0\0"
	exe.encode_u16(0x40 + 6, 1)            # one section
	exe.encode_u16(0x40 + 20, 0xF0)        # optional header size
	exe.encode_u64(0x40 + 24 + 24, BASE)   # image base
	var section := 0x40 + 24 + 0xF0
	for i in range(6):
		exe[section + i] = ".rdata".unicode_at(i)
	exe.encode_u32(section + 12, RDATA_VA)
	exe.encode_u32(section + 16, 0x40)
	exe.encode_u32(section + 20, RDATA_OFFSET)
	for i in range(6):
		exe[RDATA_OFFSET + i] = "Elwynn".unicode_at(i)
	exe.encode_u64(RDATA_OFFSET + 16, BASE + RDATA_VA)
	exe.encode_u64(RDATA_OFFSET + 24, 6)
	return exe


func test_exe_image_reads_strings_and_pointers() -> void:
	var opened := ExeImage.open(_fake_exe())
	assert_ok(opened)
	var exe: ExeImage = opened.value
	assert_eq(exe.va_to_offset(BASE + RDATA_VA + 4), RDATA_OFFSET + 4)
	assert_eq(exe.offset_to_va(RDATA_OFFSET), BASE + RDATA_VA)
	assert_eq(exe.str_at(RDATA_OFFSET + 16), "Elwynn")
	assert_eq(exe.str_at(RDATA_OFFSET), null, "text is not a pointer")
	assert_eq(exe.pointers_to(RDATA_OFFSET), PackedInt64Array([RDATA_OFFSET + 16]))
	assert_eq(exe.pointers_to(RDATA_OFFSET + 1).size(), 0)


func test_exe_image_rejects_other_files() -> void:
	assert_failed(ExeImage.open("not an exe".to_ascii_buffer()))
	var exe := _fake_exe()
	exe.encode_u32(0x40, 0)
	assert_failed(ExeImage.open(exe), "no PE signature")


func test_extract_fails_cleanly_without_tables() -> void:
	assert_failed(GameDataExtractor.extract(_fake_exe()))
