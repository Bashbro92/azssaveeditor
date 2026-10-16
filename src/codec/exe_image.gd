class_name ExeImage
extends RefCounted
## Read-only view of the game's executable: the Windows build (PE32+) or the Linux build (ELF64,
## x86-64). Gives sections, addresses and the static Rust values the game data is made of: `&str`
## and slices are (pointer, length) pairs.
##
## The Linux build is position-independent, so its pointers are stored as relocations rather than in
## place; opening it applies them, after which both formats read the same way.

enum Format { PE, ELF }

const _MAX_STR := 4000
const _ELF_MACHINE_X86_64 := 62
const _SHT_NOBITS := 8
const _R_X86_64_RELATIVE := 8
const _REX_W := [0x48, 0x49, 0x4C, 0x4D]  # REX.W prefixes a 64-bit lea can carry

var format: Format
var bytes: PackedByteArray
var _sections: Array[Dictionary] = []  # name, va, offset, size
var _string_sections: Array[Dictionary] = []   # where `&str` and slice data may live
var _pointer_sections: Array[Dictionary] = []  # where static pointers to that data live
var _code: Dictionary
var _words := {}  # section name -> PackedInt64Array of its 8-byte words, for pointer search


## Parses the section table (and, for ELF, applies relocations); fails on any other kind of file.
static func open(exe: PackedByteArray) -> Result:
	var image := ExeImage.new()
	image.bytes = exe
	var parsed: Result
	if exe.size() >= 0x40 and exe.slice(0, 2).get_string_from_ascii() == "MZ":
		image.format = Format.PE
		parsed = image._parse_pe()
	elif exe.size() >= 0x40 and exe.slice(0, 4) == PackedByteArray([0x7F, 0x45, 0x4C, 0x46]):
		image.format = Format.ELF
		parsed = image._parse_elf()
	else:
		return Result.failure("not a Windows or Linux game executable")
	if not parsed.ok:
		return parsed
	return Result.success(image)


func va_to_offset(va: int) -> int:
	for s in _sections:
		if va >= s["va"] and va < s["va"] + s["size"]:
			return s["offset"] + va - s["va"]
	return -1


func offset_to_va(offset: int) -> int:
	for s in _sections:
		if offset >= s["offset"] and offset < s["offset"] + s["size"]:
			return s["va"] + offset - s["offset"]
	return -1


func u8(o: int) -> int:
	return bytes[o]


func u32(o: int) -> int:
	return bytes.decode_u32(o)


func u64(o: int) -> int:
	return bytes.decode_u64(o)


## A slice (pointer, length) at offset o as [data offset, length], or [-1, 0] if it doesn't point
## into static data.
func slice_at(o: int) -> Array[int]:
	if o < 0 or o + 16 > bytes.size():
		return [-1, 0]
	var ptr := bytes.decode_u64(o)
	var length := bytes.decode_u64(o + 8)
	if length <= 0:
		return [-1, 0]
	for s in _string_sections:
		if ptr >= s["va"] and ptr < s["va"] + s["size"]:
			return [s["offset"] + ptr - s["va"], length]
	return [-1, 0]


## The `&str` at offset o, or null if there is none.
func str_at(o: int) -> Variant:
	var s := slice_at(o)
	return null if s[0] == -1 else text_at(s[0], s[1])


## `length` bytes at offset o as text, or null if they aren't valid UTF-8 without control
## characters (other than tab and line breaks).
func text_at(o: int, length: int) -> Variant:
	if o < 0 or length <= 0 or length > _MAX_STR or o + length > bytes.size():
		return null
	var raw := bytes.slice(o, o + length)
	return raw.get_string_from_utf8() if is_text(raw) else null


static func is_text(raw: PackedByteArray) -> bool:
	var i := 0
	while i < raw.size():
		var lead := raw[i]
		var continuation := 0
		if lead < 0x80:
			if lead < 0x20 and lead != 0x09 and lead != 0x0A and lead != 0x0D or lead == 0x7F:
				return false
		elif lead >= 0xC2 and lead <= 0xDF:
			continuation = 1
		elif lead >= 0xE0 and lead <= 0xEF:
			continuation = 2
		elif lead >= 0xF0 and lead <= 0xF4:
			continuation = 3
		else:
			return false
		if i + continuation >= raw.size():
			return false
		for k in range(1, continuation + 1):
			if raw[i + k] & 0xC0 != 0x80:
				return false
		i += continuation + 1
	return true


func find(needle: PackedByteArray, from: int = 0) -> int:
	return ByteSearch.find(bytes, needle, from)


## Offsets of 8-byte-aligned static pointers to `offset`.
func pointers_to(offset: int) -> PackedInt64Array:
	var va := offset_to_va(offset)
	var out := PackedInt64Array()
	if va == -1:
		return out
	for s in _pointer_sections:
		var words := _section_words(s)
		var i := words.find(va)
		while i != -1:
			out.append(s["offset"] + i * 8)
			i = words.find(va, i + 1)
	return out


# ---------------------------------------------------------------- x86-64 code

## Offsets of the `lea r64, [rip+d]` instructions in the code that load the address of `offset`.
func lea_refs(offset: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var va := offset_to_va(offset)
	var end: int = _code["offset"] + _code["size"]
	var p := bytes.find(0x8D, _code["offset"] + 1)
	while p != -1 and p + 6 <= end:
		if bytes[p - 1] in _REX_W and _is_rip_modrm(bytes[p + 1]) and _rip_target(p + 2, p + 6) == va:
			out.append(p - 1)
		p = bytes.find(0x8D, p + 1)
	return out


## Offsets of the `movaps xmm0-7, [rip+d]` instructions in the code that load the 16 bytes at `offset`.
func movaps_refs(offset: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var va := offset_to_va(offset)
	var end: int = _code["offset"] + _code["size"]
	var p := bytes.find(0x28, _code["offset"] + 1)
	while p != -1 and p + 6 <= end:
		if bytes[p - 1] == 0x0F and _is_rip_modrm(bytes[p + 1]) and _rip_target(p + 2, p + 6) == va:
			out.append(p - 1)
		p = bytes.find(0x28, p + 1)
	return out


## The data offsets loaded by the `movaps xmm0-7, [rip+d]` instructions found in
## [from, from + span), in order.
func movaps_loads(from: int, span: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for p in range(from, mini(from + span, bytes.size() - 7)):
		if bytes[p] == 0x0F and bytes[p + 1] == 0x28 and _is_rip_modrm(bytes[p + 2]):
			out.append(va_to_offset(_rip_target(p + 3, p + 7)))
	return out


## The strings loaded by `lea r64, [rip+d]` in [from, from + span), in order: each lea whose length
## is set by one of the next few instructions (as Rust passes a `&str` as pointer and length).
func lea_strings(from: int, span: int) -> PackedStringArray:
	var out := PackedStringArray()
	var p := bytes.find(0x8D, from + 1)
	while p != -1 and p < from + span and p + 6 < bytes.size():
		if bytes[p - 1] in _REX_W and _is_rip_modrm(bytes[p + 1]):
			var length := _length_after(p + 6)
			var text: Variant = text_at(va_to_offset(_rip_target(p + 2, p + 6)), length)
			if text != null:
				out.append(text)
		p = bytes.find(0x8D, p + 1)
	return out


## The first `mov` immediate among the (up to 3) instructions at offset o, or -1. Only the forms the
## compiler uses around a `&str` are decoded: mov r32, imm32; mov r/m64, imm32; and the register
## moves in between.
func _length_after(o: int) -> int:
	for _i in range(3):
		if o + 12 > bytes.size():
			return -1
		var rex := 0
		if bytes[o] >= 0x40 and bytes[o] <= 0x4F:
			rex = bytes[o]
			o += 1
		var op := bytes[o]
		if op >= 0xB8 and op <= 0xBF and rex & 0x08 == 0:  # mov r32, imm32
			return bytes.decode_u32(o + 1)
		if op == 0xC7 or op == 0x89 or op == 0x8B:  # mov r/m, imm32 / mov r/m, r / mov r, r/m
			var operand := _modrm_size(o + 1)
			if operand == -1:
				return -1
			if op == 0xC7:
				return bytes.decode_u32(o + 1 + operand)
			o += 1 + operand
		else:
			return -1
	return -1


## Size of a ModRM operand (ModRM byte, SIB and displacement) at offset o, or -1 for RIP-relative.
func _modrm_size(o: int) -> int:
	var modrm := bytes[o]
	var mod := modrm >> 6
	var rm := modrm & 7
	if mod == 3:
		return 1
	if mod == 0 and rm == 5:
		return -1
	var size := 1
	if rm == 4:
		size += 1
		if mod == 0 and bytes[o + 1] & 7 == 5:
			size += 4
	return size + [0, 1, 4][mod]


static func _is_rip_modrm(modrm: int) -> bool:
	return modrm & 0xC7 == 0x05


## Target address of a rip-relative operand: its disp32 at offset `disp`, the next instruction at `end`.
func _rip_target(disp: int, end: int) -> int:
	return offset_to_va(end) + bytes.decode_s32(disp)


# ---------------------------------------------------------------- formats

func _parse_pe() -> Result:
	var pe := bytes.decode_u32(0x3C)
	if pe + 24 > bytes.size() or bytes.decode_u32(pe) != 0x4550:
		return Result.failure("not a Windows executable")
	var section_count := bytes.decode_u16(pe + 6)
	var optional_size := bytes.decode_u16(pe + 20)
	var base := bytes.decode_u64(pe + 24 + 24)
	for i in range(section_count):
		var o := pe + 24 + optional_size + i * 40
		if o + 40 > bytes.size():
			return Result.failure("truncated section table")
		_sections.append({
			"name": bytes.slice(o, o + 8).get_string_from_ascii(),
			"va": base + bytes.decode_u32(o + 12),
			"size": bytes.decode_u32(o + 16),
			"offset": bytes.decode_u32(o + 20),
		})
	return _use_sections([".rdata"], [".rdata", ".data"])


func _parse_elf() -> Result:
	if bytes[4] != 2 or bytes[5] != 1 or bytes.decode_u16(0x12) != _ELF_MACHINE_X86_64:
		return Result.failure("not a 64-bit x86 Linux executable")
	var table := bytes.decode_u64(0x28)
	var entry_size := bytes.decode_u16(0x3A)
	var count := bytes.decode_u16(0x3C)
	var names_index := bytes.decode_u16(0x3E)
	if table + count * entry_size > bytes.size() or names_index >= count:
		return Result.failure("truncated section table")
	var names := bytes.decode_u64(table + names_index * entry_size + 24)
	var rela := {}
	for i in range(count):
		var o := table + i * entry_size
		var section := {
			"name": bytes.slice(names + bytes.decode_u32(o), names + bytes.decode_u32(o) + 64).get_string_from_ascii(),
			"va": bytes.decode_u64(o + 16), "offset": bytes.decode_u64(o + 24), "size": bytes.decode_u64(o + 32),
		}
		if section["name"] == ".rela.dyn":
			rela = section
		if bytes.decode_u32(o + 4) != _SHT_NOBITS and section["va"] != 0:
			_sections.append(section)
	if rela.is_empty():
		return Result.failure("no relocations (unexpected Linux build)")
	_apply_relocations(rela)
	return _use_sections([".rodata", ".data.rel.ro"], [".data.rel.ro", ".data"])


## Writes each R_X86_64_RELATIVE pointer into place (addresses as if loaded at 0, which is how the
## section table addresses them).
func _apply_relocations(rela: Dictionary) -> void:
	var entries := bytes.slice(rela["offset"], rela["offset"] + rela["size"]).to_int64_array()
	var section := {"va": 0, "size": 0, "offset": 0}
	for i in range(0, entries.size() - 2, 3):
		if entries[i + 1] & 0xFFFFFFFF != _R_X86_64_RELATIVE:
			continue
		var va := entries[i]
		if va < section["va"] or va + 8 > section["va"] + section["size"]:
			section = _section_at(va)
			if section.is_empty():
				section = {"va": 0, "size": 0, "offset": 0}
				continue
		bytes.encode_s64(section["offset"] + va - section["va"], entries[i + 2])


func _use_sections(strings: Array[String], pointers: Array[String]) -> Result:
	for name in strings:
		_string_sections.append(_section(name))
	for name in pointers:
		_pointer_sections.append(_section(name))
	_code = _section(".text")
	if _code.is_empty() or _string_sections.has({}) or _pointer_sections[0].is_empty():
		return Result.failure("unexpected section layout")
	_pointer_sections.erase({})
	return Result.success()


func _section(name: String) -> Dictionary:
	for s in _sections:
		if s["name"] == name:
			return s
	return {}


func _section_at(va: int) -> Dictionary:
	for s in _sections:
		if va >= s["va"] and va < s["va"] + s["size"]:
			return s
	return {}


func _section_words(s: Dictionary) -> PackedInt64Array:
	if not _words.has(s["name"]):
		@warning_ignore("integer_division")
		var size: int = mini(s["size"], bytes.size() - s["offset"]) / 8 * 8
		_words[s["name"]] = bytes.slice(s["offset"], s["offset"] + size).to_int64_array()
	return _words[s["name"]]
