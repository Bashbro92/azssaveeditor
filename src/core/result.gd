class_name Result
extends RefCounted
## Outcome of a fallible operation: a value on success, an error message on failure.

var ok: bool = false
var value: Variant = null
var error: String = ""


static func success(result_value: Variant = null) -> Result:
	var r := Result.new()
	r.ok = true
	r.value = result_value
	return r


static func failure(message: String) -> Result:
	var r := Result.new()
	r.error = message
	return r
