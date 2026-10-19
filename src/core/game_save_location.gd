class_name GameSaveLocation
extends RefCounted
## Where the game keeps its save (0.100.1 to 0.102.x), on every platform.
##
## Data folder (exe 0x87c2880): the folder of WOW_ROGUE_SAVE when it is set, else $APPDATA, else $XDG_DATA_HOME, else
## $HOME/.local/share, each followed by "wenilla-rogue". So %APPDATA%\wenilla-rogue on Windows and
## ~/.local/share/wenilla-rogue on Linux (and macOS, which takes the same branch).
## Save file (exe 0x87c2b00): WOW_ROGUE_SAVE itself when set, else characters.txt in the data folder.
## Exports and the hourly backups go to its Saves folder, which the game's Options, Saves page lists for importing.

const SAVE_ENV := "WOW_ROGUE_SAVE"
const FOLDER := "wenilla-rogue"
const SAVE_NAME := "characters.txt"
const SAVES := "Saves"


## The data folder, from the environment `env` (name -> value, or null when unset), or "" if there is none.
static func data_dir(env: Callable) -> String:
	var save: Variant = env.call(SAVE_ENV)
	if save != null:
		return str(save).get_base_dir()
	for name in ["APPDATA", "XDG_DATA_HOME"]:
		var dir: Variant = env.call(name)
		if dir != null:
			return str(dir).path_join(FOLDER)
	var home: Variant = env.call("HOME")
	return "" if home == null else str(home).path_join(".local").path_join("share").path_join(FOLDER)


## The save file, from the environment `env`, or "" if there is none.
static func save_file(env: Callable) -> String:
	var save: Variant = env.call(SAVE_ENV)
	if save != null:
		return str(save)
	var dir := data_dir(env)
	return "" if dir == "" else dir.path_join(SAVE_NAME)


## The Saves folder (exports and backups), from the environment `env`, or "" if there is none.
static func saves_dir(env: Callable) -> String:
	var dir := data_dir(env)
	return "" if dir == "" else dir.path_join(SAVES)


## The process environment, for the functions above.
static func os_env(name: String) -> Variant:
	if OS.has_environment(name):
		return OS.get_environment(name)
	return null
