class_name ExeImage
extends RefCounted
## Read-only view of the game's Windows exe (PE32+): sections, addresses and the static Rust values
## the game data is made of: `&str` and slices are (pointer, length) pairs into `.rdata`.

const _MAX_STR := 4000

var bytes: PackedByteArray
var _sections: Array[Dictionary] = []  # name, va, offset, size
var _rdata: Dictionary
var _words := {}  # section name -> PackedInt64Array of its 8-byte words, for pointer search


## Parses the section table; fails on anything that isn't a PE32+ image with an .rdata section.
static func open(exe: PackedByteArray) -> Result:
	if exe.size() < 0x40 or exe.slice(0, 2).get_string_from_ascii() != "MZ":
		return Result.failure("not a Windows executable")
	var pe := exe.decode_u32(0x3C)
	if pe + 24 > exe.size() or exe.decode_u32(pe) != 0x4550:
		return Result.failure("not a Windows executable")
	var image := ExeImage.new()
	image.bytes = exe
	var section_count := exe.decode_u16(pe + 6)
	var optional_size := exe.decode_u16(pe + 20)
	var base := exe.decode_u64(pe + 24 + 24)
	for i in range(section_count):
		var o := pe + 24 + optional_size + i * 40
		if o + 40 > exe.size():
			return Result.failure("truncated section table")
		image._sections.append({
			"name": exe.slice(o, o + 8).get_string_from_ascii(),
			"va": base + exe.decode_u32(o + 12),
			"size": exe.decode_u32(o + 16),
			"offset": exe.decode_u32(o + 20),
		})
	image._rdata = image._section(".rdata")
	if image._rdata.is_empty():
		return Result.failure("no .rdata section")
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
## into .rdata.
func slice_at(o: int) -> Array[int]:
	if o < 0 or o + 16 > bytes.size():
		return [-1, 0]
	var ptr := bytes.decode_u64(o)
	var length := bytes.decode_u64(o + 8)
	if length <= 0 or ptr < _rdata["va"] or ptr >= _rdata["va"] + _rdata["size"]:
		return [-1, 0]
	return [_rdata["offset"] + ptr - _rdata["va"], length]


## The `&str` at offset o, or null if there is none.
func str_at(o: int) -> Variant:
	var s := slice_at(o)
	if s[0] == -1 or s[1] > _MAX_STR or s[0] + s[1] > bytes.size():
		return null
	var raw := bytes.slice(s[0], s[0] + s[1])
	var text := raw.get_string_from_utf8()
	# invalid UTF-8 or an embedded NUL shortens the text: then it isn't a string
	return text if text.to_utf8_buffer().size() == raw.size() else null


func find(needle: PackedByteArray, from: int = 0) -> int:
	return ByteSearch.find(bytes, needle, from)


## Offsets of 8-byte-aligned pointers to `offset` in .rdata and .data.
func pointers_to(offset: int) -> PackedInt64Array:
	var va := offset_to_va(offset)
	var out := PackedInt64Array()
	if va == -1:
		return out
	for name: String in [".rdata", ".data"]:
		var s := _section(name)
		if s.is_empty():
			continue
		var words := _section_words(name, s)
		var i := words.find(va)
		while i != -1:
			out.append(s["offset"] + i * 8)
			i = words.find(va, i + 1)
	return out


func _section(name: String) -> Dictionary:
	for s in _sections:
		if s["name"] == name:
			return s
	return {}


func _section_words(name: String, s: Dictionary) -> PackedInt64Array:
	if not _words.has(name):
		@warning_ignore("integer_division")
		var size: int = mini(s["size"], bytes.size() - s["offset"]) / 8 * 8
		_words[name] = bytes.slice(s["offset"], s["offset"] + size).to_int64_array()
	return _words[name]
