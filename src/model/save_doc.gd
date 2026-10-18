class_name SaveDoc
extends RefCounted
## Plaintext save: one `kind|field|field…` record per line.
##
## Every line is kept, including unknown kinds, empty lines and the original order, so writing back
## an unmodified document reproduces the input exactly.

const FIELD_SEPARATOR := "|"
const LINE_SEPARATOR := "\n"

## Each record is the line split on "|"; element 0 is the record kind.
var records: Array[PackedStringArray] = []
var _trailing_newline := false


static func parse(text: String) -> SaveDoc:
	var doc := SaveDoc.new()
	doc._trailing_newline = text.ends_with(LINE_SEPARATOR)
	var body := text.substr(0, text.length() - 1) if doc._trailing_newline else text
	if body.is_empty() and not doc._trailing_newline:
		return doc
	for line in body.split(LINE_SEPARATOR):
		doc.records.append(line.split(FIELD_SEPARATOR))
	return doc


func to_text() -> String:
	var lines := PackedStringArray()
	for record in records:
		lines.append(FIELD_SEPARATOR.join(record))
	var text := LINE_SEPARATOR.join(lines)
	return text + LINE_SEPARATOR if _trailing_newline else text


## All records of a kind, in document order.
func records_of(kind: String) -> Array[PackedStringArray]:
	var found: Array[PackedStringArray] = []
	for record in records:
		if record[0] == kind:
			found.append(record)
	return found


## The first record of a kind, or an empty array if there is none.
func first(kind: String) -> PackedStringArray:
	for record in records:
		if record[0] == kind:
			return record
	return PackedStringArray()


## Replaces all records of a kind with `replacement`, placed where the first one was. If the kind was
## absent, they go right after the last record of kind `after`, or at the end if there is none. Other
## records keep their order.
func replace_kind(kind: String, replacement: Array[PackedStringArray], after: String = "") -> void:
	var updated: Array[PackedStringArray] = []
	var inserted := false
	var at := -1
	for record in records:
		if record[0] != kind:
			updated.append(record)
			if after != "" and record[0] == after:
				at = updated.size()
		elif not inserted:
			updated.append_array(replacement)
			inserted = true
	if not inserted:
		if at == -1:
			updated.append_array(replacement)
		else:
			for i in range(replacement.size()):
				updated.insert(at + i, replacement[i])
	records = updated
