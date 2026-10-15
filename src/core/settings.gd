class_name Settings
extends RefCounted
## Persistent editor settings: where the user's game exe and Data folder are, and the last folder used.

const DEFAULT_PATH := "user://settings.cfg"
const _SECTION := "paths"

var exe_path := ""
var data_dir := ""
var last_dir := ""
var _path: String


static func load_from(path: String = DEFAULT_PATH) -> Settings:
	var s := Settings.new()
	s._path = path
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		s.exe_path = cfg.get_value(_SECTION, "exe_path", "")
		s.data_dir = cfg.get_value(_SECTION, "data_dir", "")
		s.last_dir = cfg.get_value(_SECTION, "last_dir", "")
	return s


func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, "exe_path", exe_path)
	cfg.set_value(_SECTION, "data_dir", data_dir)
	cfg.set_value(_SECTION, "last_dir", last_dir)
	return cfg.save(_path)
