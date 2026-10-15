class_name SaveCodec
extends RefCounted
## Seals and unseals Azeroth Survivors save text.
##
## A sealed save is "RSE1:" + base64(header[16] | ciphertext | tag[20]), where
##   tag        = HMAC-SHA1(key, "tag" + header + ciphertext)
##   ciphertext = plaintext XOR keystream
##   keystream block n (20 bytes) = HMAC-SHA1(key, "ks" + header + u64 little-endian n)

const MAGIC := "RSE1:"
const HEADER_SIZE := 16
const TAG_SIZE := 20
const BLOCK_SIZE := 20

const _TAG_LABEL := "tag"
const _KEYSTREAM_LABEL := "ks"
const _BASE64_PATTERN := "^[A-Za-z0-9+/]*={0,2}$"


## Sealed save text -> plaintext. Fails on a bad prefix, bad base64, a short body or a tag mismatch.
static func unseal(key: PackedByteArray, sealed: String) -> Result:
	var text := sealed.strip_edges()
	if not text.begins_with(MAGIC):
		return Result.failure("not a sealed save (no %s prefix)" % MAGIC)
	var body := text.substr(MAGIC.length())
	if not _is_base64(body):
		return Result.failure("save body is not valid base64")
	var raw := Marshalls.base64_to_raw(body)
	if raw.size() < HEADER_SIZE + TAG_SIZE:
		return Result.failure("save is too short")

	var header := raw.slice(0, HEADER_SIZE)
	var ciphertext := raw.slice(HEADER_SIZE, raw.size() - TAG_SIZE)
	var tag := raw.slice(raw.size() - TAG_SIZE)
	if not _equal_constant_time(_tag(key, header, ciphertext), tag):
		return Result.failure("tag mismatch: wrong key or the save was modified")
	return Result.success(_xor_keystream(key, header, ciphertext).get_string_from_utf8())


## Plaintext -> sealed save text. Uses a fresh random header unless one is given (for tests).
static func seal(key: PackedByteArray, plain: String, header: PackedByteArray = PackedByteArray()) -> Result:
	if header.is_empty():
		header = Crypto.new().generate_random_bytes(HEADER_SIZE)
	if header.size() != HEADER_SIZE:
		return Result.failure("header must be %d bytes" % HEADER_SIZE)
	var ciphertext := _xor_keystream(key, header, plain.to_utf8_buffer())
	var raw := header + ciphertext + _tag(key, header, ciphertext)
	return Result.success(MAGIC + Marshalls.raw_to_base64(raw))


static func _tag(key: PackedByteArray, header: PackedByteArray, ciphertext: PackedByteArray) -> PackedByteArray:
	return _hmac_sha1(key, _TAG_LABEL.to_ascii_buffer() + header + ciphertext)


static func _xor_keystream(key: PackedByteArray, header: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	var prefix := _KEYSTREAM_LABEL.to_ascii_buffer() + header
	var counter := PackedByteArray()
	counter.resize(8)
	for start in range(0, out.size(), BLOCK_SIZE):
		@warning_ignore("integer_division")
		counter.encode_u64(0, start / BLOCK_SIZE)
		var block := _hmac_sha1(key, prefix + counter)
		for i in range(mini(BLOCK_SIZE, out.size() - start)):
			out[start + i] ^= block[i]
	return out


static func _hmac_sha1(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA1, key, message)


static func _equal_constant_time(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in range(a.size()):
		diff |= a[i] ^ b[i]
	return diff == 0


static func _is_base64(text: String) -> bool:
	if text.is_empty() or text.length() % 4 != 0:
		return false
	var regex := RegEx.create_from_string(_BASE64_PATTERN)
	return regex.search(text) != null
