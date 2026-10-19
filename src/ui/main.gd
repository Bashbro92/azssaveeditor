extends Control
## Main window: game-file setup, open/save, the 100% fill and the editor tabs.

var session := EditorSession.new()
var settings := Settings.load_from()
var _status := Label.new()
var _version := Label.new()
var _save_button: Button
var _fill_button: Button
var _tabs := TabContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(_toolbar())
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for panel in _panels():
		_tabs.add_child(panel)
		panel.bind(session)
	root.add_child(_tabs)
	session.edited.connect(func() -> void: _set_unsaved(true))
	session.configured.connect(_show_version)
	_configure_from_settings()


func _panels() -> Array[EditorPanel]:
	var panels: Array[EditorPanel] = [OverviewPanel.new(), ZonesPanel.new(), TalentsPanel.new(),
			CollectionPanel.new(), CodexPanel.new(), AchievementsPanel.new(), PerksPanel.new()]
	for panel in panels:
		panel.name = panel.get_script().get_global_name().trim_suffix("Panel")
	return panels


func _toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_child(_button("Game files…", _choose_exe))
	bar.add_child(_button("Open save…", _choose_save_to_open))
	_save_button = _button("Save as…", _choose_save_target)
	bar.add_child(_save_button)
	_fill_button = _button("Fill 100%", session.fill_all)
	_fill_button.tooltip_text = "Unlock everything: heroes, zones, gear, codex, achievements, talent XP."
	bar.add_child(_fill_button)
	bar.add_child(_spacer())
	bar.add_child(_version)
	bar.add_child(_spacer())
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)
	return bar


static func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


# ---------------------------------------------------------------- game files

func _configure_from_settings() -> void:
	if settings.exe_path.is_empty():
		_show_status("Choose the game (AzerothSurvivors.exe or the Linux AzerothSurvivors) with “Game files…”.")
		_update_buttons()
		return
	var configured := session.configure(settings.exe_path, settings.data_dir)
	_show_status("Ready. Open a save." if configured.ok else configured.error)
	_update_buttons()


func _choose_exe() -> void:
	var filters := PackedStringArray(["*.exe, AzerothSurvivors ; Game executable (Windows or Linux)", "* ; All files"])
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, filters, "Select the game executable",
			func(path: String) -> void:
				settings.exe_path = path
				settings.data_dir = path.get_base_dir().path_join("Data")
				settings.save()
				_configure_from_settings())


# ---------------------------------------------------------------- saves

func _choose_save_to_open() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.sav ; Azeroth Survivors save"], "Open save", open_save_file)


func open_save_file(path: String) -> void:
	var opened := session.open_save(path)
	if opened.ok:
		_remember_dir(path)
		_set_unsaved(false)
	_show_status(path.get_file() if opened.ok else opened.error)
	_update_buttons()


func _choose_save_target() -> void:
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.sav ; Azeroth Survivors save"], "Save as",
			func(path: String) -> void:
				var saved := session.save_as(path)
				if saved.ok:
					_remember_dir(path)
					_set_unsaved(false)
				_show_status("Saved " + path.get_file() if saved.ok else saved.error))


func _remember_dir(path: String) -> void:
	settings.last_dir = path.get_base_dir()
	settings.save()


func tab_count() -> int:
	return _tabs.get_tab_count()


func show_tab(index: int) -> void:
	_tabs.current_tab = index


# ---------------------------------------------------------------- helpers

func _file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray, title: String, on_pick: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.title = title
	dialog.use_native_dialog = true
	if settings.last_dir:
		dialog.current_dir = settings.last_dir
	dialog.file_selected.connect(on_pick)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _set_unsaved(unsaved: bool) -> void:
	var title := "AZS Save Editor"
	if session.save_path:
		title += " — " + session.save_path.get_file()
	get_window().title = title + (" *" if unsaved else "")


func _update_buttons() -> void:
	_save_button.disabled = not session.has_save()
	_fill_button.disabled = not session.has_save()


func _show_version() -> void:
	_version.text = "Game " + session.game_version if session.game_version else ""


func _show_status(text: String) -> void:
	_status.text = text
