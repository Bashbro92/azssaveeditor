class_name VersionFinder
extends RefCounted
## Reads the game version (e.g. "0.94.1") from the user's own AzerothSurvivors.exe.
##
## The game's update check keeps its own version as a string literal right before two of its
## messages. Each anchor gives a candidate; the shortest wins, as a neighbouring literal that ends in
## a digit can only make a candidate longer.

const ANCHORS: Array[String] = ["A new version is out!", "update: up to date (site has v"]
const _MAX_GAP := 4  # non-text bytes allowed between the version and an anchor
const _MAX_LENGTH := 20


static func find_version(exe: PackedByteArray) -> String:
	var best := ""
	for anchor in ANCHORS:
		var at := ByteSearch.find(exe, anchor.to_ascii_buffer())
		if at == -1:
			continue
		var version := _version_before(exe, at)
		if version and (best.is_empty() or version.length() < best.length()):
			best = version
	return best


## The `major.minor.patch` that ends right before `at` (after at most _MAX_GAP non-text bytes), or "".
static func _version_before(exe: PackedByteArray, at: int) -> String:
	var end := at
	while end > 0 and at - end < _MAX_GAP and not _is_text(exe[end - 1]):
		end -= 1
	var start := end
	while start > 0 and end - start < _MAX_LENGTH and _is_version_char(exe[start - 1]):
		start -= 1
	var text := exe.slice(start, end).get_string_from_ascii().lstrip(".").rstrip(".")
	var parts := text.split(".")
	if parts.size() != 3:
		return ""
	for part in parts:
		if part.is_empty() or not part.is_valid_int():
			return ""
	return text


static func _is_text(byte: int) -> bool:
	return byte >= 0x20 and byte <= 0x7e


static func _is_version_char(byte: int) -> bool:
	return (byte >= 0x30 and byte <= 0x39) or byte == 0x2e
