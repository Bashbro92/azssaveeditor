extends TestCase

const SAMPLE := "pick|1|1|1|duskwood|Broisar|4,5,2,4,0|100,100,100,100\nunlock|1|2\nlook|1|\nbeat|1|elwynn\nbeat|1|duskwood\nfuture|kind|kept"


func test_round_trip_is_exact() -> void:
	for text in [SAMPLE, SAMPLE + "\n", "", "\n", "a||b\n\nc"]:
		assert_eq(SaveDoc.parse(text).to_text(), text, "input %s" % text.c_escape())


func test_splits_fields() -> void:
	var doc := SaveDoc.parse(SAMPLE)
	assert_eq(doc.records.size(), 6)
	assert_eq(doc.records[1], PackedStringArray(["unlock", "1", "2"]))


func test_keeps_empty_fields() -> void:
	assert_eq(SaveDoc.parse(SAMPLE).first("look"), PackedStringArray(["look", "1", ""]))


func test_records_of_kind_in_order() -> void:
	var beats := SaveDoc.parse(SAMPLE).records_of("beat")
	assert_eq(beats.size(), 2)
	assert_eq(beats[0][2], "elwynn")
	assert_eq(beats[1][2], "duskwood")


func test_unknown_kinds_are_kept() -> void:
	assert_eq(SaveDoc.parse(SAMPLE).first("future"), PackedStringArray(["future", "kind", "kept"]))


func test_first_of_missing_kind_is_empty() -> void:
	assert_true(SaveDoc.parse(SAMPLE).first("perk").is_empty())


func test_empty_text_has_no_records() -> void:
	assert_eq(SaveDoc.parse("").records.size(), 0)


func test_replace_kind_in_place() -> void:
	var doc := SaveDoc.parse(SAMPLE)
	var beats: Array[PackedStringArray] = [PackedStringArray(["beat", "1", "x"])]
	doc.replace_kind("beat", beats)
	assert_eq(doc.to_text(), SAMPLE.replace("beat|1|elwynn\nbeat|1|duskwood", "beat|1|x"))


func test_replace_kind_appends_new_kind() -> void:
	var doc := SaveDoc.parse("a|1")
	var added: Array[PackedStringArray] = [PackedStringArray(["perk", "2"]), PackedStringArray(["perk", "3"])]
	doc.replace_kind("perk", added)
	assert_eq(doc.to_text(), "a|1\nperk|2\nperk|3")


func test_replace_kind_inserts_a_new_kind_after_another() -> void:
	var doc := SaveDoc.parse("a|1\nb|1\nb|2\nc|1\n")
	var added: Array[PackedStringArray] = [PackedStringArray(["d", "1"]), PackedStringArray(["d", "2"])]
	doc.replace_kind("d", added, "b")
	assert_eq(doc.to_text(), "a|1\nb|1\nb|2\nd|1\nd|2\nc|1\n")
	var more: Array[PackedStringArray] = [PackedStringArray(["e", "1"])]
	doc.replace_kind("e", more, "missing")
	assert_eq(doc.to_text(), "a|1\nb|1\nb|2\nd|1\nd|2\nc|1\ne|1\n", "at the end without one")


func test_replace_kind_with_nothing_removes_it() -> void:
	var doc := SaveDoc.parse(SAMPLE)
	var none: Array[PackedStringArray] = []
	doc.replace_kind("beat", none)
	assert_true(doc.records_of("beat").is_empty())
	assert_eq(doc.records.size(), 4)
