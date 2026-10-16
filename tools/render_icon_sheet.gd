extends SceneTree
## Renders every icon referenced by the game data into one PNG sheet, to check BLP decoding by eye.
##
##   godot --headless --script tools/render_icon_sheet.gd -- <game executable> <out.png>
##
## Icons come from the Data folder next to the executable.

const ICON_SIZE := 64
const COLUMNS := 24
const ICON_PATH := "Interface\\Icons\\%s.blp"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: godot --headless --script tools/render_icon_sheet.gd -- <game executable> <out.png>")
		quit(2)
		return
	quit(_render(args[0], args[1]))


func _render(exe_path: String, out_path: String) -> int:
	var bytes := KeyFinder.read_exe(exe_path)
	var exe := ExeImage.open(bytes.value) if bytes.ok else bytes
	var game := GameData.from_exe(exe.value) if exe.ok else exe
	var opened := MpqArchive.open(exe_path.get_base_dir().path_join("Data/patch.MPQ"))
	for r in [game, opened]:
		if not r.ok:
			printerr(r.error)
			return 1
	var archive: MpqArchive = opened.value
	var names: PackedStringArray = game.value.icon_names()
	var rows := ceili(float(names.size()) / COLUMNS)
	var sheet := Image.create_empty(COLUMNS * ICON_SIZE, rows * ICON_SIZE, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.15))
	var failed := PackedStringArray()
	for i in range(names.size()):
		var file := archive.read_file(ICON_PATH % names[i])
		var image := BlpImage.decode(file.value) if file.ok else file
		if not image.ok:
			failed.append("%s: %s" % [names[i], image.error])
			continue
		var icon: Image = image.value
		@warning_ignore("integer_division")
		var at := Vector2i(i % COLUMNS, i / COLUMNS) * ICON_SIZE
		sheet.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), at)
	sheet.save_png(out_path)
	print("%d icons, %d failed -> %s" % [names.size(), failed.size(), out_path])
	for f in failed:
		printerr("  " + f)
	return 1 if failed else 0
