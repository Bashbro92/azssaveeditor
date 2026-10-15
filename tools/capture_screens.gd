extends SceneTree
## Opens a save in the real main window and writes a screenshot of every tab, for reviewing the UI.
## Needs a display (not --headless); the user's saved settings are not changed.
##
##   godot --script tools/capture_screens.gd -- <AzerothSurvivors.exe> <save.sav> <out dir>

const MAIN_SCENE := "res://src/ui/main.tscn"
const SETTLE_FRAMES := 10


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("usage: godot --script tools/capture_screens.gd -- <exe> <save.sav> <out dir>")
		quit(2)
		return
	_capture.call_deferred(args[0], args[1], args[2])


func _capture(exe: String, save_path: String, out_dir: String) -> void:
	var main: Control = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	var configured: Result = main.session.configure(exe, exe.get_base_dir().path_join("Data"))
	if not configured.ok:
		printerr(configured.error)
		quit(1)
		return
	main.open_save_file(save_path)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for i in range(main.tab_count()):
		main.show_tab(i)
		for _f in range(SETTLE_FRAMES):
			await process_frame
		var path := out_dir.path_join("tab_%d.png" % i)
		root.get_texture().get_image().save_png(path)
		print("wrote ", path)
	main.queue_free()
	await process_frame
	quit(0)
