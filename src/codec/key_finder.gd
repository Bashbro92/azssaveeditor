class_name KeyFinder
extends RefCounted
## Recovers the save key from the user's own AzerothSurvivors.exe.
##
## The exe stores the key as HMAC's precomputed inner-pad block (key XOR 0x36), padded to 64 bytes.
## The Windows build keeps the block in one piece; the Linux build keeps it as four 16-byte constants
## that the code loads one after another, found from the load of the first one. A known start of the
## key locates the block; the key ends where the rest of its 16-byte chunk is all padding (zero once
## un-XORed).

const KEY_PREFIX := "azeroth-survivors/sa"
const _INNER_PAD := 0x36
const _BLOCK_SIZE := 64
const _CHUNK_SIZE := 16
const _CHUNKS := 4  # _BLOCK_SIZE / _CHUNK_SIZE


static func find_key_in_file(exe_path: String) -> Result:
	var bytes := read_exe(exe_path)
	if not bytes.ok:
		return bytes
	var image := ExeImage.open(bytes.value)
	return find_key(bytes.value, image.value if image.ok else null)


## The whole exe, as the key and the game version are both read from it.
static func read_exe(exe_path: String) -> Result:
	if not FileAccess.file_exists(exe_path):
		return Result.failure("file not found: %s" % exe_path)
	var bytes := FileAccess.get_file_as_bytes(exe_path)
	if bytes.is_empty():
		return Result.failure("could not read %s: %s" % [exe_path, error_string(FileAccess.get_open_error())])
	return Result.success(bytes)


## The key from the exe's bytes; `image` (the same exe, opened) is needed for the Linux layout.
static func find_key(exe: PackedByteArray, image: ExeImage = null) -> Result:
	var block := _stored_block(exe)
	if block.is_empty() and image != null:
		block = _loaded_block(image)
	if block.is_empty():
		return Result.failure("save key not found (different game build or save scheme?)")
	block = _xor(block, _INNER_PAD)
	for end in range(KEY_PREFIX.length(), block.size()):
		@warning_ignore("integer_division")
		var chunk_end := (end / _CHUNK_SIZE + 1) * _CHUNK_SIZE
		if _all_zero(block.slice(end, chunk_end)):
			return Result.success(block.slice(0, end))
	return Result.success(block)


## The inner-pad block stored in one piece, or empty.
static func _stored_block(exe: PackedByteArray) -> PackedByteArray:
	var at := ByteSearch.find(exe, _xor(KEY_PREFIX.to_ascii_buffer(), _INNER_PAD))
	return PackedByteArray() if at == -1 else exe.slice(at, at + _BLOCK_SIZE)


## The inner-pad block as the four chunks loaded after the first one, or empty.
static func _loaded_block(image: ExeImage) -> PackedByteArray:
	var first := _xor(KEY_PREFIX.to_ascii_buffer().slice(0, _CHUNK_SIZE), _INNER_PAD)
	var at := image.find(first)
	while at != -1:
		for load in image.movaps_refs(at):
			var chunks := image.movaps_loads(load, _BLOCK_SIZE)
			if chunks.size() >= _CHUNKS and chunks[0] == at:
				var block := PackedByteArray()
				for chunk in chunks.slice(0, _CHUNKS):
					block.append_array(image.bytes.slice(chunk, chunk + _CHUNK_SIZE))
				return block
		at = image.find(first, at + 1)
	return PackedByteArray()


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
