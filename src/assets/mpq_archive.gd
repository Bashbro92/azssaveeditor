class_name MpqArchive
extends RefCounted
## Read-only MPQ (format v0/v1) archive: header, encrypted hash/block tables, file lookup and reads.
##
## Supports stored files and zlib-compressed sectors, which covers the game's patch archives. Encrypted
## files, PKWARE implode and other codecs are reported as errors, never guessed at.

const _SIGNATURE := 0x1A51504D           # "MPQ\x1A"
const _USER_DATA_SIGNATURE := 0x1B51504D # "MPQ\x1B"
const _HASH_EMPTY := 0xFFFFFFFF
const _FLAG_IMPLODE := 0x00000100
const _FLAG_COMPRESS := 0x00000200
const _FLAG_ENCRYPTED := 0x00010000
const _FLAG_SINGLE_UNIT := 0x01000000
const _FLAG_DELETE_MARKER := 0x02000000
const _FLAG_EXISTS := 0x80000000
const _COMPRESSION_ZLIB := 0x02
const _MASK32 := 0xFFFFFFFF

static var _crypt_table := PackedInt64Array()

var _file: FileAccess
var _base := 0
var _sector_size := 0
var _hashes := PackedInt64Array()  # 4 per entry: name_a, name_b, locale/platform, block index
var _blocks := PackedInt64Array()  # 4 per entry: offset, compressed size, file size, flags


static func open(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("could not open %s: %s" % [path, error_string(FileAccess.get_open_error())])
	var archive := MpqArchive.new()
	var err := archive._read_index(file)
	if err:
		return Result.failure("%s: %s" % [path, err])
	return Result.success(archive)


func has_file(name: String) -> bool:
	var block := _find_block(name)
	return block != -1 and not (_blocks[block * 4 + 3] & _FLAG_DELETE_MARKER)


func read_file(name: String) -> Result:
	var block := _find_block(name)
	if block == -1:
		return Result.failure("not in archive: %s" % name)
	var offset := _blocks[block * 4]
	var stored_size := _blocks[block * 4 + 1]
	var size := _blocks[block * 4 + 2]
	var flags := _blocks[block * 4 + 3]
	if flags & _FLAG_DELETE_MARKER:
		return Result.failure("deleted in archive: %s" % name)
	if flags & _FLAG_ENCRYPTED:
		return Result.failure("encrypted file not supported: %s" % name)
	if flags & _FLAG_IMPLODE:
		return Result.failure("PKWARE implode not supported: %s" % name)

	_file.seek(_base + offset)
	var raw := _file.get_buffer(stored_size)
	if not (flags & _FLAG_COMPRESS):
		return Result.success(raw.slice(0, size))
	if flags & _FLAG_SINGLE_UNIT:
		return _decompress(raw, size)

	var sectors := ceili(float(size) / _sector_size)
	var data := PackedByteArray()
	for i in range(sectors):
		var start := raw.decode_u32(i * 4)
		var end := raw.decode_u32((i + 1) * 4)
		var sector := _decompress(raw.slice(start, end), mini(_sector_size, size - i * _sector_size))
		if not sector.ok:
			return Result.failure("%s: %s" % [name, sector.error])
		data.append_array(sector.value)
	return Result.success(data)


## The archive's "(listfile)" as a list of names, if it has one.
func list_files() -> PackedStringArray:
	var listing := read_file("(listfile)")
	if not listing.ok:
		return PackedStringArray()
	var names := PackedStringArray()
	for line: String in listing.value.get_string_from_utf8().split("\n", false):
		var name := line.strip_edges()
		if name:
			names.append(name)
	return names


## MPQ string hash of the given type (0 = table offset, 1 = name A, 2 = name B, 3 = table key).
static func hash_string(text: String, hash_type: int) -> int:
	_ensure_crypt_table()
	var seed1 := 0x7FED7FED
	var seed2 := 0xEEEEEEEE
	for c in text.to_upper().to_ascii_buffer():
		seed1 = (_crypt_table[(hash_type << 8) + c] ^ (seed1 + seed2)) & _MASK32
		seed2 = (c + seed1 + seed2 + (seed2 << 5) + 3) & _MASK32
	return seed1


static func decrypt_block(data: PackedByteArray, key: int) -> PackedByteArray:
	_ensure_crypt_table()
	var out := data.duplicate()
	var seed2 := 0xEEEEEEEE
	@warning_ignore("integer_division")
	var words := out.size() / 4
	for i in range(words):
		seed2 = (seed2 + _crypt_table[0x400 + (key & 0xFF)]) & _MASK32
		var value := (out.decode_u32(i * 4) ^ (key + seed2)) & _MASK32
		key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & _MASK32
		seed2 = (value + seed2 + (seed2 << 5) + 3) & _MASK32
		out.encode_u32(i * 4, value)
	return out


func _read_index(file: FileAccess) -> String:
	_file = file
	var header_at := _find_header(file)
	if header_at == -1:
		return "not an MPQ archive"
	_base = header_at
	file.seek(header_at + 12)  # after signature, header size and archive size
	var format_version := file.get_16()
	if format_version > 1:
		return "unsupported MPQ format version %d" % format_version
	_sector_size = 512 << file.get_16()
	var hash_pos := file.get_32()
	var block_pos := file.get_32()
	var hash_count := file.get_32()
	var block_count := file.get_32()
	if hash_count == 0 or (_base + hash_pos + hash_count * 16) > file.get_length():
		return "corrupt hash table"
	if (_base + block_pos + block_count * 16) > file.get_length():
		return "corrupt block table"
	_hashes = _read_table(file, hash_pos, hash_count, hash_string("(hash table)", 3))
	_blocks = _read_table(file, block_pos, block_count, hash_string("(block table)", 3))
	return ""


func _read_table(file: FileAccess, pos: int, count: int, key: int) -> PackedInt64Array:
	file.seek(_base + pos)
	var bytes := decrypt_block(file.get_buffer(count * 16), key)
	var table := PackedInt64Array()
	table.resize(count * 4)
	for i in range(count * 4):
		table[i] = bytes.decode_u32(i * 4)
	return table


func _find_block(name: String) -> int:
	@warning_ignore("integer_division")
	var count := _hashes.size() / 4
	@warning_ignore("integer_division")
	var block_count := _blocks.size() / 4
	var name_a := hash_string(name, 1)
	var name_b := hash_string(name, 2)
	var start := hash_string(name, 0) % count
	var i := start
	while true:
		var block := _hashes[i * 4 + 3]
		if block == _HASH_EMPTY:
			return -1
		if _hashes[i * 4] == name_a and _hashes[i * 4 + 1] == name_b and block < block_count:
			return block if _blocks[block * 4 + 3] & _FLAG_EXISTS else -1
		i = (i + 1) % count
		if i == start:
			return -1
	return -1


static func _find_header(file: FileAccess) -> int:
	var pos := 0
	while pos + 32 <= file.get_length():
		file.seek(pos)
		var signature := file.get_32()
		if signature == _SIGNATURE:
			return pos
		if signature == _USER_DATA_SIGNATURE:
			file.seek(pos + 8)
			return pos + file.get_32()
		pos += 512
	return -1


static func _decompress(data: PackedByteArray, size: int) -> Result:
	if data.size() == size:
		return Result.success(data)
	if data.is_empty() or data[0] != _COMPRESSION_ZLIB:
		return Result.failure("unsupported sector compression 0x%02x" % (data[0] if data.size() else 0))
	var out := data.slice(1).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if out.size() != size:
		return Result.failure("zlib sector did not inflate to %d bytes" % size)
	return Result.success(out)


static func _ensure_crypt_table() -> void:
	if not _crypt_table.is_empty():
		return
	_crypt_table.resize(0x500)
	var table_seed := 0x00100001
	for i in range(0x100):
		var index := i
		for _j in range(5):
			table_seed = (table_seed * 125 + 3) % 0x2AAAAB
			var high := (table_seed & 0xFFFF) << 16
			table_seed = (table_seed * 125 + 3) % 0x2AAAAB
			_crypt_table[index] = high | (table_seed & 0xFFFF)
			index += 0x100
