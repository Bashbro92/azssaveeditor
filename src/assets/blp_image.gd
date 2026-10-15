class_name BlpImage
extends RefCounted
## Decodes the top mip level of a BLP2 texture (WoW 1.12) into an RGBA8 Image.
##
## Supports DXT1/DXT3/DXT5 (decompressed through Godot's S3TC support) and 256-colour palettes with
## 0, 1, 4 or 8 bits of alpha. Uncompressed and JPEG BLPs are reported as unsupported.

const _HEADER_SIZE := 148
const _PALETTE_SIZE := 256 * 4
const _COMPRESSION_PALETTE := 1
const _COMPRESSION_DXT := 2
const _ALPHA_DXT1 := 0
const _ALPHA_DXT3 := 1
const _ALPHA_DXT5 := 7


static func decode(data: PackedByteArray) -> Result:
	if data.size() < _HEADER_SIZE or data.slice(0, 4).get_string_from_ascii() != "BLP2":
		return Result.failure("not a BLP2 texture")
	var compression := data[8]
	var alpha_depth := data[9]
	var alpha_encoding := data[10]
	var width := data.decode_u32(12)
	var height := data.decode_u32(16)
	var mip_offset := data.decode_u32(20)
	var mip_size := data.decode_u32(84)
	if width == 0 or height == 0 or width > 4096 or height > 4096:
		return Result.failure("bad BLP size %dx%d" % [width, height])
	if mip_size == 0 or mip_offset + mip_size > data.size():
		return Result.failure("BLP mip 0 lies outside the file")
	var mip := data.slice(mip_offset, mip_offset + mip_size)

	match compression:
		_COMPRESSION_DXT:
			return _decode_dxt(mip, width, height, alpha_encoding, alpha_depth)
		_COMPRESSION_PALETTE:
			return _decode_palette(data.slice(_HEADER_SIZE, _HEADER_SIZE + _PALETTE_SIZE), mip,
					width, height, alpha_depth)
	return Result.failure("unsupported BLP compression %d" % compression)


static func _decode_dxt(mip: PackedByteArray, width: int, height: int, alpha_encoding: int,
		alpha_depth: int) -> Result:
	var format: Image.Format
	match alpha_encoding:
		_ALPHA_DXT1:
			format = Image.FORMAT_DXT1
		_ALPHA_DXT3:
			format = Image.FORMAT_DXT3
		_ALPHA_DXT5:
			format = Image.FORMAT_DXT5
		_:
			return Result.failure("unsupported DXT alpha encoding %d" % alpha_encoding)
	var block_bytes := 8 if format == Image.FORMAT_DXT1 else 16
	@warning_ignore("integer_division")
	var expected := maxi(1, (width + 3) / 4) * maxi(1, (height + 3) / 4) * block_bytes
	if mip.size() < expected:
		return Result.failure("DXT data too short (%d < %d)" % [mip.size(), expected])
	var image := Image.create_from_data(width, height, false, format, mip.slice(0, expected))
	if image.decompress() != OK:
		return Result.failure("could not decompress DXT texture")
	image.convert(Image.FORMAT_RGBA8)
	if format == Image.FORMAT_DXT1 and alpha_depth == 0:
		_make_opaque(image)
	return Result.success(image)


static func _decode_palette(palette: PackedByteArray, mip: PackedByteArray, width: int, height: int,
		alpha_depth: int) -> Result:
	var pixels := width * height
	@warning_ignore("integer_division")
	var alpha_bytes := (pixels * alpha_depth + 7) / 8
	if palette.size() < _PALETTE_SIZE or mip.size() < pixels + alpha_bytes:
		return Result.failure("palette BLP data too short")
	var rgba := PackedByteArray()
	rgba.resize(pixels * 4)
	for i in range(pixels):
		var p := mip[i] * 4  # palette entries are BGRA
		rgba[i * 4] = palette[p + 2]
		rgba[i * 4 + 1] = palette[p + 1]
		rgba[i * 4 + 2] = palette[p]
		rgba[i * 4 + 3] = _palette_alpha(mip, pixels, i, alpha_depth)
	return Result.success(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba))


static func _palette_alpha(mip: PackedByteArray, alpha_start: int, i: int, depth: int) -> int:
	match depth:
		1:
			@warning_ignore("integer_division")
			return 255 if (mip[alpha_start + i / 8] >> (i % 8)) & 1 else 0
		4:
			@warning_ignore("integer_division")
			return ((mip[alpha_start + i / 2] >> ((i % 2) * 4)) & 0xF) * 17
		8:
			return mip[alpha_start + i]
	return 255


static func _make_opaque(image: Image) -> void:
	var data := image.get_data()
	for i in range(3, data.size(), 4):
		data[i] = 255
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
