class_name ByteSearch
extends RefCounted
## Substring search in raw bytes (an exe is ~130 MB, so candidates are checked byte by byte before
## anything is copied).


## Offset of the first `needle` in `haystack` at or after `from`, or -1.
static func find(haystack: PackedByteArray, needle: PackedByteArray, from: int = 0) -> int:
	if needle.is_empty():
		return -1
	var last := haystack.size() - needle.size()
	var at := haystack.find(needle[0], from)
	while at != -1 and at <= last:
		var i := 1
		while i < needle.size() and haystack[at + i] == needle[i]:
			i += 1
		if i == needle.size():
			return at
		at = haystack.find(needle[0], at + 1)
	return -1
