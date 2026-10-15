class_name TestCase
extends RefCounted
## Base class for tests: methods named `test_*` are run by tests/run_tests.gd.

var failures := PackedStringArray()
var skip_reason := ""


## Override to prepare state shared by all tests of a case; call skip() to skip the whole case.
func before_all() -> void:
	pass


## Override to clean up after all tests of a case have run.
func after_all() -> void:
	pass


func skip(reason: String) -> void:
	skip_reason = reason


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		failures.append(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%sexpected %s, got %s" % [message + ": " if message else "", _show(expected), _show(actual)])


func assert_ok(result: Result, message: String = "") -> void:
	if not result.ok:
		failures.append("%sexpected success, got error: %s" % [message + ": " if message else "", result.error])


func assert_failed(result: Result, message: String = "") -> void:
	if result.ok:
		failures.append("%sexpected failure, got success" % [message + ": " if message else ""])


func _show(value: Variant) -> String:
	var text := var_to_str(value)
	return text if text.length() <= 120 else text.substr(0, 117) + "..."
