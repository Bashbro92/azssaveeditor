extends TestCase


## A BLP2 file with the given header fields, an optional palette, and `mip` as mip level 0.
func _blp(compression: int, alpha_depth: int, alpha_encoding: int, width: int, height: int,
		mip: PackedByteArray, palette: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(148)
	data.encode_u32(0, 0x32504C42)  # "BLP2"
	data.encode_u32(4, 1)
	data[8] = compression
	data[9] = alpha_depth
	data[10] = alpha_encoding
	data.encode_u32(12, width)
	data.encode_u32(16, height)
	if compression == 1:
		palette.resize(1024)
		data.append_array(palette)
	data.encode_u32(20, data.size())
	data.encode_u32(84, mip.size())
	data.append_array(mip)
	return data


## One DXT1 colour block: colour0 (RGB565), colour1, then 2-bit indices (all 0 = colour0).
func _dxt1_block(color0: int, color1: int, indices: int = 0) -> PackedByteArray:
	var block := PackedByteArray()
	block.resize(8)
	block.encode_u16(0, color0)
	block.encode_u16(2, color1)
	block.encode_u32(4, indices)
	return block


func test_dxt1_solid_red() -> void:
	var result := BlpImage.decode(_blp(2, 0, 0, 4, 4, _dxt1_block(0xF800, 0x0000)))
	assert_ok(result)
	var image: Image = result.value
	assert_eq(image.get_size(), Vector2i(4, 4))
	assert_eq(image.get_pixel(1, 2), Color(1, 0, 0, 1))


func test_dxt1_without_alpha_is_opaque() -> void:
	# colour0 <= colour1 selects 3-colour mode, where index 3 means transparent black
	var image: Image = BlpImage.decode(_blp(2, 0, 0, 4, 4, _dxt1_block(0x0000, 0xFFFF, 0xFFFFFFFF))).value
	assert_eq(image.get_pixel(0, 0).a, 1.0)


func test_dxt3_explicit_alpha() -> void:
	var alpha := PackedByteArray()
	alpha.resize(8)
	alpha.fill(0x00)  # 4-bit alpha 0 everywhere
	var image: Image = BlpImage.decode(_blp(2, 8, 1, 4, 4, alpha + _dxt1_block(0x07E0, 0x0000))).value
	assert_eq(image.get_pixel(3, 3), Color(0, 1, 0, 0))


func test_palette_with_8bit_alpha() -> void:
	var palette := PackedByteArray([0, 0, 255, 0, 255, 0, 0, 0])  # BGRA: red, blue
	var mip := PackedByteArray([0, 1, 1, 0, 255, 128, 0, 255])    # 2x2 indices, then alpha
	var image: Image = BlpImage.decode(_blp(1, 8, 8, 2, 2, mip, palette)).value
	assert_eq(image.get_pixel(0, 0), Color(1, 0, 0, 1))
	assert_eq(image.get_pixel(1, 0).b, 1.0)
	assert_eq(image.get_pixel(1, 0).a8, 128)
	assert_eq(image.get_pixel(0, 1).a, 0.0)


func test_palette_with_1bit_alpha() -> void:
	var palette := PackedByteArray([255, 255, 255, 0])
	var mip := PackedByteArray([0, 0, 0, 0, 0b0101])  # pixels 0 and 2 visible
	var image: Image = BlpImage.decode(_blp(1, 1, 8, 2, 2, mip, palette)).value
	assert_eq(image.get_pixel(0, 0).a, 1.0)
	assert_eq(image.get_pixel(1, 0).a, 0.0)
	assert_eq(image.get_pixel(0, 1).a, 1.0)


func test_palette_without_alpha_is_opaque() -> void:
	var image: Image = BlpImage.decode(_blp(1, 0, 8, 2, 1, PackedByteArray([0, 0]))).value
	assert_eq(image.get_pixel(1, 0).a, 1.0)


func test_rejects_bad_input() -> void:
	assert_failed(BlpImage.decode(PackedByteArray()))
	assert_failed(BlpImage.decode("BLP1".to_ascii_buffer()), "BLP1 magic")
	assert_failed(BlpImage.decode(_blp(2, 0, 0, 4, 4, PackedByteArray([1, 2]))), "short DXT data")
	assert_failed(BlpImage.decode(_blp(3, 0, 0, 4, 4, _dxt1_block(0, 0))), "uncompressed BLP")
	assert_failed(BlpImage.decode(_blp(2, 0, 5, 4, 4, _dxt1_block(0, 0))), "unknown alpha encoding")
