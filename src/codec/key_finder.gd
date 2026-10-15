class_name KeyFinder
extends RefCounted
## Recovers the save key from the user's own AzerothSurvivors.exe.
##
## The exe stores the key as HMAC's precomputed inner-pad block (key XOR 0x36), padded and split into
## 16-byte chunks. A known start of the key locates that block; the key ends where the rest of its
## chunk is all padding (zero once un-XORed).

const KEY_PREFIX := "azeroth-survivors/sa"
const _INNER_PAD := 0x36
const _BLOCK_SIZE := 64
const _CHUNK_SIZE := 16


static func find_key_in_file(exe_path: String) -> Result:
	if not FileAccess.file_exists(exe_path):
		return Result.failure("file not found: %s" % exe_path)
	var bytes := FileAccess.get_file_as_bytes(exe_path)
	if bytes.is_empty():
		return Result.failure("could not read %s: %s" % [exe_path, error_string(FileAccess.get_open_error())])
	return find_key(bytes)


static func find_key(exe: PackedByteArray) -> Result:
	var needle := _xor(KEY_PREFIX.to_ascii_buffer(), _INNER_PAD)
	var at := _find(exe, needle)
	if at == -1:
		return Result.failure("save key not found (different game build or save scheme?)")
	var block := _xor(exe.slice(at, at + _BLOCK_SIZE), _INNER_PAD)
	for end in range(needle.size(), block.size()):
		@warning_ignore("integer_division")
		var chunk_end := (end / _CHUNK_SIZE + 1) * _CHUNK_SIZE
		if _all_zero(block.slice(end, chunk_end)):
			return Result.success(block.slice(0, end))
	return Result.success(block)


static func _find(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	var from := 0
	while true:
		var at := haystack.find(needle[0], from)
		if at == -1 or at + needle.size() > haystack.size():
			return -1
		if haystack.slice(at, at + needle.size()) == needle:
			return at
		from = at + 1
	return -1


static func _xor(data: PackedByteArray, mask: int) -> PackedByteArray:
	var out := data.duplicate()
	for i in range(out.size()):
		out[i] ^= mask
	return out


static func _all_zero(data: PackedByteArray) -> bool:
	for b in data:
		if b != 0:
			return false
	return true
