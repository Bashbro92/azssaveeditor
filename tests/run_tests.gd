extends SceneTree
## Headless test runner: godot --headless --script tests/run_tests.gd
## Runs every `test_*` method of every tests/test_*.gd script. A test fails on a failed assertion or on
## any script error raised while it runs; a test file that doesn't load fails as a whole. Exits with 1
## if anything failed.

const TEST_DIR := "res://tests/"


## Collects engine and script errors so a test that crashes can't pass silently.
class ErrorCollector extends Logger:
	var errors := PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var collector := ErrorCollector.new()
	OS.add_logger(collector)
	var passed := 0
	var failed := 0
	var skipped := 0
	for file in _test_files():
		collector.errors.clear()
		var script: Script = load(TEST_DIR + file)
		var case: TestCase = script.new() if script and script.can_instantiate() else null
		if case == null or not collector.errors.is_empty():
			failed += 1
			_report(file, "<load>", ["could not load test script"] + Array(collector.errors))
			continue
		case.before_all()
		if case.skip_reason:
			skipped += 1
			print("SKIP %s: %s" % [file, case.skip_reason])
			continue
		for method in case.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			case.failures.clear()
			collector.errors.clear()
			case.call(name)
			var problems := Array(case.failures) + Array(collector.errors)
			if problems.is_empty():
				passed += 1
			else:
				failed += 1
				_report(file, name, problems)
		case.after_all()
	OS.remove_logger(collector)
	print("\n%d passed, %d failed, %d skipped case(s)" % [passed, failed, skipped])
	quit(1 if failed > 0 else 0)


func _report(file: String, test: String, problems: Array) -> void:
	print("FAIL %s::%s\n  %s" % [file, test, "\n  ".join(PackedStringArray(problems))])


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()
	return files
