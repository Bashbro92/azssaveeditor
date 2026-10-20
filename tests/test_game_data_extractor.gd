extends TestCase
## The extractor's pure helpers, and ExeImage and KeyFinder on tiny synthetic Windows and Linux
## executables. The real game is covered by test_real_game_data.gd.

const BLOCK: Array[String] = ["Fully Talented", "Earn all {n} talent points with one class.", "Collector",
		"Hoarder", "Slaughterhouse", "Slay 2,500 enemies in one run.", "Thrifty",
		"Win a run without buying a cache."]

const PE_BASE := 0x140000000
const RDATA_VA := 0x1000
const RDATA_OFFSET := 0x200

## Synthetic ELF layout: file offsets equal addresses, except .text (to test the mapping).
const ELF_RODATA := 0x100
const ELF_KEY_CHUNKS := [0x140, 0x170, 0x150, 0x160]  # where key chunks 0-3 are stored
const ELF_DATA_REL_RO := 0x200
const ELF_RELA := 0x240
const ELF_TEXT := 0x300
const ELF_TEXT_VA := 0x1300
const ELF_SHSTRTAB := 0x380
const ELF_SECTIONS := 0x400
const ELF_KEY := KeyFinder.KEY_PREFIX + "-linux-key"


func _assemble(strings: Array) -> Dictionary:
	var out := {}
	for a: Dictionary in GameDataExtractor.assemble_achievements(PackedStringArray(strings), BLOCK):
		out[a["name"]] = a
	return out


func test_achievement_fields_in_builder_order() -> void:
	var got := _assemble(["Fully Talented", "Earn all {n} talent points with one class.", "INV_Misc_Book_11"])
	assert_eq(got["Fully Talented"], {"name": "Fully Talented", "key": "talents:1", "icon": "INV_Misc_Book_11",
			"description": "Earn all 51 talent points with one class.", "group": "Classes"})


func test_keys_and_icons_follow_in_a_later_run() -> void:
	var got := _assemble(["Slaughterhouse", "Slay 2,500 enemies in one run.", "Thrifty",
			"Win a run without buying a cache.", "feat:kills2500", "Ability_Whirlwind", "feat:thrifty", "INV_Box_01"])
	assert_eq([got["Slaughterhouse"]["key"], got["Slaughterhouse"]["icon"]], ["feat:kills2500", "Ability_Whirlwind"])
	assert_eq([got["Thrifty"]["key"], got["Thrifty"]["icon"]], ["feat:thrifty", "INV_Box_01"])
	assert_eq(got["Thrifty"]["group"], "Feats")


func test_code_built_achievements_take_icons_but_not_loaded_keys() -> void:
	var got := _assemble(["Collector", "Hoarder", "Slaughterhouse", "INV_Chest_Chain", "INV_Chest_Plate16",
			"feat:kills2500", "Ability_Whirlwind"])
	assert_eq(got["Collector"]["icon"], "INV_Chest_Chain")
	assert_eq(got["Hoarder"]["icon"], "INV_Chest_Plate16")
	assert_eq(got["Hoarder"]["key"], "pieces:100")
	assert_eq(got["Hoarder"]["description"], "Collect 100 pieces of gear, of any class.")
	assert_eq(got["Slaughterhouse"]["key"], "feat:kills2500", "the first achievement with a loaded key")


func test_ignores_what_follows_the_builder() -> void:
	var got := _assemble(["Thrifty", "feat:thrifty", "INV_Box_01", "Thrifty", "count:runs10", "INV_Box_02",
			"Achievement earned:", "n"])
	assert_eq(got.size(), 1)
	assert_eq([got["Thrifty"]["key"], got["Thrifty"]["icon"]], ["feat:thrifty", "INV_Box_01"])


func test_later_achievements_are_the_texts_after_the_last_enemy_name() -> void:
	var keys := ["Fully Talented", "Jan", "enemy.1414", "enemy.1415", "Sapphiron", "no u",
			"Slay Sapphiron with a Frostbolt as the killing blow."]
	assert_eq(GameDataExtractor.later_achievement_texts(keys),
			["Sapphiron", "no u", "Slay Sapphiron with a Frostbolt as the killing blow."] as Array[String], "0.103.1")
	assert_eq(GameDataExtractor.later_achievement_texts(["Fully Talented", "Jan"]), [] as Array[String])


func test_drops_achievements_without_a_key() -> void:
	assert_eq(_assemble(["Slaughterhouse", "Slay 2,500 enemies in one run."]), {})


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


# ---------------------------------------------------------------- Windows (PE32+)

## A minimal PE32+ image: headers, a .rdata section at RDATA_OFFSET holding "Elwynn" followed by a
## `&str` (pointer, length) to it, and an empty .text section.
func _fake_pe() -> PackedByteArray:
	var exe := PackedByteArray()
	exe.resize(RDATA_OFFSET + 0x40)
	exe.encode_u16(0, 0x5A4D)                # "MZ"
	exe.encode_u32(0x3C, 0x40)               # PE header offset
	exe.encode_u32(0x40, 0x4550)             # "PE\0\0"
	exe.encode_u16(0x40 + 6, 2)              # two sections
	exe.encode_u16(0x40 + 20, 0xF0)          # optional header size
	exe.encode_u64(0x40 + 24 + 24, PE_BASE)  # image base
	var section := 0x40 + 24 + 0xF0
	_put(exe, section, ".rdata")
	exe.encode_u32(section + 12, RDATA_VA)
	exe.encode_u32(section + 16, 0x40)
	exe.encode_u32(section + 20, RDATA_OFFSET)
	_put(exe, section + 40, ".text")
	_put(exe, RDATA_OFFSET, "Elwynn")
	exe.encode_u64(RDATA_OFFSET + 16, PE_BASE + RDATA_VA)
	exe.encode_u64(RDATA_OFFSET + 24, 6)
	return exe


func test_pe_strings_and_pointers() -> void:
	var opened := ExeImage.open(_fake_pe())
	assert_ok(opened)
	var image: ExeImage = opened.value
	assert_eq(image.format, ExeImage.Format.PE)
	assert_eq(image.va_to_offset(PE_BASE + RDATA_VA + 4), RDATA_OFFSET + 4)
	assert_eq(image.str_at(RDATA_OFFSET + 16), "Elwynn")
	assert_eq(image.str_at(RDATA_OFFSET), null, "text is not a pointer")
	assert_eq(image.pointers_to(RDATA_OFFSET), PackedInt64Array([RDATA_OFFSET + 16]))


func test_is_text() -> void:
	assert_true(ExeImage.is_text("Ahn'Qiraj\n".to_utf8_buffer()))
	assert_true(ExeImage.is_text("Prankenhieb verursacht über".to_utf8_buffer()))
	assert_false(ExeImage.is_text(PackedByteArray([0x1E])), "control character")
	assert_false(ExeImage.is_text(PackedByteArray([0x41, 0x00])), "NUL")
	assert_false(ExeImage.is_text(PackedByteArray([0x8D, 0x41])), "stray continuation byte")
	assert_false(ExeImage.is_text(PackedByteArray([0xC3])), "truncated sequence")


func test_rejects_other_files() -> void:
	assert_failed(ExeImage.open("not an exe".to_ascii_buffer()))
	var exe := _fake_pe()
	exe.encode_u32(0x40, 0)
	assert_failed(ExeImage.open(exe), "no PE signature")
	var elf := _fake_elf()
	elf.encode_u16(0x12, 3)
	assert_failed(ExeImage.open(elf), "not x86-64")


# ---------------------------------------------------------------- Linux (ELF64)

## A minimal x86-64 ELF: "Elwynn" in .rodata with a `&str` to it in .data.rel.ro that only a
## relocation fills in, the save key's inner-pad block as four scattered chunks, and code that
## loads both the way the game does.
func _fake_elf() -> PackedByteArray:
	var exe := PackedByteArray()
	exe.resize(ELF_SECTIONS + 6 * 64)
	_put(exe, 0, "\u007FELF")
	exe[4] = 2  # 64-bit
	exe[5] = 1  # little-endian
	exe.encode_u16(0x12, 62)  # x86-64
	exe.encode_u64(0x28, ELF_SECTIONS)
	exe.encode_u16(0x3A, 64)
	exe.encode_u16(0x3C, 6)
	exe.encode_u16(0x3E, 5)

	_put(exe, ELF_RODATA, "Elwynn")
	var block := ELF_KEY.to_ascii_buffer()
	block.resize(64)
	for i in range(64):
		@warning_ignore("integer_division")
		exe[ELF_KEY_CHUNKS[i / 16] + i % 16] = block[i] ^ 0x36
	exe.encode_u64(ELF_DATA_REL_RO + 8, 6)  # the pointer itself stays 0 until relocated
	exe.encode_u64(ELF_RELA, ELF_DATA_REL_RO)
	exe.encode_u64(ELF_RELA + 8, 8)  # R_X86_64_RELATIVE
	exe.encode_u64(ELF_RELA + 16, ELF_RODATA)

	var code := PackedByteArray([0x48, 0x8D, 0x05, 0, 0, 0, 0, 0xBE, 6, 0, 0, 0])  # lea rax, ["Elwynn"]; mov esi, 6
	code.encode_s32(3, ELF_RODATA - (ELF_TEXT_VA + 7))
	for chunk: int in ELF_KEY_CHUNKS:
		var movaps := PackedByteArray([0x0F, 0x28, 0x05, 0, 0, 0, 0, 0x0F, 0x29, 0x44, 0x24, 0x30])  # movaps; store
		movaps.encode_s32(3, chunk - (ELF_TEXT_VA + code.size() + 7))
		code.append_array(movaps)
	for i in range(code.size()):
		exe[ELF_TEXT + i] = code[i]

	var sections := [  # name, type, address, offset, size
		[".rodata", 1, ELF_RODATA, ELF_RODATA, 0x100], [".data.rel.ro", 1, ELF_DATA_REL_RO, ELF_DATA_REL_RO, 0x40],
		[".rela.dyn", 4, ELF_RELA, ELF_RELA, 24], [".text", 1, ELF_TEXT_VA, ELF_TEXT, 0x80],
		[".shstrtab", 3, 0, ELF_SHSTRTAB, 0x80],
	]
	var name_at := 1  # the names table starts with an empty name
	for i in range(sections.size()):
		var o: int = ELF_SECTIONS + (i + 1) * 64
		var s: Array = sections[i]
		_put(exe, ELF_SHSTRTAB + name_at, s[0])
		exe.encode_u32(o, name_at)
		name_at += s[0].length() + 1
		exe.encode_u32(o + 4, s[1])
		exe.encode_u64(o + 16, s[2])
		exe.encode_u64(o + 24, s[3])
		exe.encode_u64(o + 32, s[4])
	return exe


func test_elf_relocated_strings_and_pointers() -> void:
	var opened := ExeImage.open(_fake_elf())
	assert_ok(opened)
	var image: ExeImage = opened.value
	assert_eq(image.format, ExeImage.Format.ELF)
	assert_eq(image.va_to_offset(ELF_TEXT_VA + 4), ELF_TEXT + 4)
	assert_eq(image.str_at(ELF_DATA_REL_RO), "Elwynn", "pointer filled in from its relocation")
	assert_eq(image.pointers_to(ELF_RODATA), PackedInt64Array([ELF_DATA_REL_RO]))


func test_elf_code_references() -> void:
	var image: ExeImage = ExeImage.open(_fake_elf()).value
	assert_eq(image.lea_refs(ELF_RODATA), PackedInt64Array([ELF_TEXT]))
	assert_eq(image.lea_strings(ELF_TEXT, 0x80), PackedStringArray(["Elwynn"]))
	assert_eq(image.movaps_refs(ELF_KEY_CHUNKS[0]), PackedInt64Array([ELF_TEXT + 12]))
	assert_eq(image.movaps_loads(ELF_TEXT, 0x80), PackedInt64Array(ELF_KEY_CHUNKS))


func test_key_from_scattered_chunks() -> void:
	var exe := _fake_elf()
	var result := KeyFinder.find_key(exe, ExeImage.open(exe).value)
	assert_ok(result)
	assert_eq(result.value, ELF_KEY.to_ascii_buffer())
	assert_failed(KeyFinder.find_key(exe), "needs the image for the Linux layout")


func test_extract_fails_cleanly_without_tables() -> void:
	assert_failed(GameDataExtractor.extract(ExeImage.open(_fake_elf()).value))


static func _put(exe: PackedByteArray, at: int, text: String) -> void:
	for i in range(text.length()):
		exe[at + i] = text.unicode_at(i)
