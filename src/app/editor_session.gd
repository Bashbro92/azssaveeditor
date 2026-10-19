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


## Reads the key, version and game data from the exe and opens the Data folder's patch.MPQ for
## icons. Icons are optional.
func configure(exe_path: String, data_dir: String) -> Result:
	var bytes := KeyFinder.read_exe(exe_path)
	var exe := ExeImage.open(bytes.value) if bytes.ok else bytes
	if not exe.ok:
		return exe
	var found := KeyFinder.find_key(bytes.value, exe.value)
	if not found.ok:
		return found
	var loaded := GameData.from_exe(exe.value)
	if not loaded.ok:
		return loaded
	key = found.value
	game_version = VersionFinder.find_version(bytes.value)
	game = loaded.value
	var archive := MpqArchive.open(data_dir.path_join("patch.MPQ"))
	icons = IconCache.new(archive.value if archive.ok else null)
	configured.emit()
	return Result.success()


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
	progress = read_save(plain.value)
	save_path = path
	save_changed.emit()
	return Result.success()


## A save's plain text read as the game reads it, with this game's zones and its talent sets relearned.
func read_save(text: String) -> SaveProgress:
	var zones: Array[String] = []
	zones.assign(game.zone_ids())
	var read := SaveProgress.from_text(text, zones)
	read.relearn_talents(trees_of)
	return read


## A WoW class id's three talent trees, empty for a class the game doesn't have.
func trees_of(wow_class_id: int) -> Array:
	var c := game.class_by_wow_id(wow_class_id)
	return [] if c.is_empty() else game.trees_for_class(c["id"])


## Seals the current save to `path`, as the game writes it: talent sets relearned (talents a spec can't hold, e.g.
## past its points, are dropped, as the game drops them on reading), then the game's lines in the game's order. An
## existing file there is kept as `<path>.bak`.
func save_as(path: String) -> Result:
	if progress == null:
		return Result.failure("no save is open")
	var before := progress.to_text()
	progress.relearn_talents(trees_of)
	var text := progress.to_text()
	if text != before:
		save_changed.emit()
	var sealed := SaveCodec.seal(key, text)
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


## The name the game gives an exported save at unix time `now` (in UTC): "AzerothSurvivors 2026-10-19 08-05-09.sav".
static func export_name(now: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(now)
	return "AzerothSurvivors %04d-%02d-%02d %02d-%02d-%02d.sav" % [t["year"], t["month"], t["day"], t["hour"],
			t["minute"], t["second"]]
