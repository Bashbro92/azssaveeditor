extends TestCase
## Where the game keeps its save, from a given environment.


static func _env(values: Dictionary) -> Callable:
	return func(name: String) -> Variant: return values.get(name)


func test_windows_uses_appdata() -> void:
	var env := _env({"APPDATA": "C:/Users/me/AppData/Roaming", "HOME": "/home/me"})
	assert_eq(GameSaveLocation.save_file(env), "C:/Users/me/AppData/Roaming/wenilla-rogue/characters.txt")
	assert_eq(GameSaveLocation.saves_dir(env), "C:/Users/me/AppData/Roaming/wenilla-rogue/Saves")


func test_linux_uses_xdg_data_home_else_home() -> void:
	assert_eq(GameSaveLocation.save_file(_env({"XDG_DATA_HOME": "/data", "HOME": "/home/me"})),
			"/data/wenilla-rogue/characters.txt")
	assert_eq(GameSaveLocation.save_file(_env({"HOME": "/home/me"})),
			"/home/me/.local/share/wenilla-rogue/characters.txt")
	assert_eq(GameSaveLocation.saves_dir(_env({"HOME": "/home/me"})), "/home/me/.local/share/wenilla-rogue/Saves")


func test_wow_rogue_save_names_the_file() -> void:
	var env := _env({"WOW_ROGUE_SAVE": "/games/azs/mine.txt", "APPDATA": "C:/x"})
	assert_eq(GameSaveLocation.save_file(env), "/games/azs/mine.txt")
	assert_eq(GameSaveLocation.saves_dir(env), "/games/azs/Saves")


func test_no_environment_no_folder() -> void:
	assert_eq(GameSaveLocation.save_file(_env({})), "")
	assert_eq(GameSaveLocation.saves_dir(_env({})), "")
