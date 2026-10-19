extends TestCase
## Session and settings behaviour with temporary files under user:// and a test key.

const TMP := "user://test_tmp/"
const KEY := "test-key-not-the-real-one"
const PLAIN := "open|1|cave\nstat|kills=1"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)


func after_all() -> void:
	for file in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP + file)
	DirAccess.remove_absolute(TMP)


func _fresh_session() -> EditorSession:
	var s := EditorSession.new()
	s.key = KEY.to_ascii_buffer()
	s.game = GameData.load_file("res://tests/fixtures/game_data_min.json").value
	return s


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _sealed_save(name: String) -> String:
	var path := TMP + name
	_write(path, SaveCodec.seal(KEY.to_ascii_buffer(), PLAIN).value)
	return path


func test_open_and_save_round_trip() -> void:
	var s := _fresh_session()
	assert_ok(s.open_save(_sealed_save("a.sav")))
	s.progress.set_stat("kills", 5)
	var out := TMP + "b.sav"
	DirAccess.remove_absolute(out)
	assert_ok(s.save_as(out))
	var reopened := _fresh_session()
	assert_ok(reopened.open_save(out))
	assert_eq(reopened.progress.stat("kills"), 5)
	assert_eq(reopened.progress.zones_unlocked(1), 2)


func test_saves_what_the_game_would_write() -> void:
	var s := _fresh_session()
	var path := TMP + "e.sav"
	_write(path, SaveCodec.seal(KEY.to_ascii_buffer(), "future|x\nbeat|1|cave,meadow\ntalent|1|80|t1:3,zz:1\n").value)
	assert_ok(s.open_save(path))
	assert_true(s.progress.is_beaten(1, "meadow"))
	assert_eq(s.progress.talent_rank(1, "t1"), 1, "relearned within the points, as the game reads it")
	var out := TMP + "f.sav"
	assert_ok(s.save_as(out))
	var plain := SaveCodec.unseal(KEY.to_ascii_buffer(), FileAccess.get_file_as_string(out))
	assert_eq(plain.value, "talent|1|80|t1:1\nbeat|1|meadow,cave\n")


func test_export_name_is_the_games() -> void:
	assert_eq(EditorSession.export_name(1792080337), "AzerothSurvivors 2026-10-15 16-05-37.sav")
	assert_eq(EditorSession.export_name(0), "AzerothSurvivors 1970-01-01 00-00-00.sav")


func test_save_over_existing_keeps_backup() -> void:
	var s := _fresh_session()
	var path := _sealed_save("c.sav")
	var original := FileAccess.get_file_as_string(path)
	s.open_save(path)
	s.progress.set_stat("kills", 9)
	assert_ok(s.save_as(path))
	assert_eq(FileAccess.get_file_as_string(path + ".bak"), original)
	assert_true(FileAccess.get_file_as_string(path) != original)


func test_open_rejects_tampered_or_missing_file() -> void:
	var s := _fresh_session()
	var path := TMP + "bad.sav"
	_write(path, "RSE1:AAAA")
	assert_failed(s.open_save(path))
	assert_failed(s.open_save(TMP + "missing.sav"))
	assert_false(s.has_save())


func test_save_without_open_save_fails() -> void:
	assert_failed(_fresh_session().save_as(TMP + "x.sav"))


func test_open_emits_save_changed() -> void:
	var s := _fresh_session()
	var seen := [0]
	s.save_changed.connect(func() -> void: seen[0] += 1)
	s.open_save(_sealed_save("d.sav"))
	assert_eq(seen[0], 1)


func test_configure_reports_missing_exe() -> void:
	assert_failed(EditorSession.new().configure(TMP + "no.exe", TMP))


func test_settings_round_trip() -> void:
	var path := TMP + "settings.cfg"
	var s := Settings.load_from(path)
	s.exe_path = "/games/AzerothSurvivors.exe"
	s.data_dir = "/games/Data"
	assert_eq(s.save(), OK)
	var loaded := Settings.load_from(path)
	assert_eq(loaded.exe_path, "/games/AzerothSurvivors.exe")
	assert_eq(loaded.data_dir, "/games/Data")


func test_settings_default_when_missing() -> void:
	assert_eq(Settings.load_from(TMP + "none.cfg").exe_path, "")


func test_icon_cache_without_archive_returns_null() -> void:
	assert_eq(IconCache.new().get_icon("Ability_Warrior_Cleave"), null)

