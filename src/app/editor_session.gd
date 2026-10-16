class_name EditorSession
extends RefCounted
## The editor's working state: save key, game data, icons and the open save.

## A different save was opened or the whole save changed (e.g. a 100% fill): views should reload.
signal save_changed
## The open save was edited and has unsaved changes.
signal edited
## Game files were (re)loaded: key, game version and game data.
signal configured

var key := PackedByteArray()
var game_version := ""  # read from the exe; "" if not found
var game: GameData
var icons := IconCache.new()
var progress: SaveProgress
var save_path := ""


## Reads the key from the exe and opens the Data folder's patch.MPQ for icons. Icons are optional.
func configure(exe_path: String, data_dir: String, game_data_path: String = GameData.DEFAULT_PATH) -> Result:
	var exe := KeyFinder.read_exe(exe_path)
	if not exe.ok:
		return exe
	var found := KeyFinder.find_key(exe.value)
	if not found.ok:
		return found
	var loaded := GameData.load_file(game_data_path)
	if not loaded.ok:
		return loaded
	key = found.value
	game_version = VersionFinder.find_version(exe.value)
	game = loaded.value
	var archive := MpqArchive.open(data_dir.path_join("patch.MPQ"))
	icons = IconCache.new(archive.value if archive.ok else null)
	configured.emit()
	return Result.success()


## Whether the game data was extracted from a different game version than the chosen exe (data
## generated before versions were recorded counts as different).
func data_outdated() -> bool:
	return game != null and game_version != "" and game.game_version != game_version


func is_configured() -> bool:
	return not key.is_empty() and game != null


func has_save() -> bool:
	return progress != null


func open_save(path: String) -> Result:
	if not FileAccess.file_exists(path):
		return Result.failure("file not found: %s" % path)
	var plain := SaveCodec.unseal(key, FileAccess.get_file_as_string(path))
	if not plain.ok:
		return plain
	progress = SaveProgress.from_text(plain.value)
	save_path = path
	save_changed.emit()
	return Result.success()


## Seals the current save to `path`. An existing file there is kept as `<path>.bak`.
func save_as(path: String) -> Result:
	if progress == null:
		return Result.failure("no save is open")
	var sealed := SaveCodec.seal(key, progress.to_text())
	if not sealed.ok:
		return sealed
	if FileAccess.file_exists(path):
		var err := DirAccess.copy_absolute(path, path + ".bak")
		if err != OK:
			return Result.failure("could not back up %s: %s" % [path, error_string(err)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(sealed.value)
	file.close()
	save_path = path
	return Result.success()


## Everything unlocked (see SaveProgress.fill_all); views reload.
func fill_all() -> void:
	if progress == null:
		return
	progress.fill_all(game, int(Time.get_unix_time_from_system()))
	save_changed.emit()
	edited.emit()


func mark_edited() -> void:
	edited.emit()
