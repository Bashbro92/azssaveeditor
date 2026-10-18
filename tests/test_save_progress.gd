extends TestCase

const SAMPLE := "pick|1|1|1|meadow|Hero|4,5,2,4,0|100,100,100,100\n" \
		+ "open|1|cave\n" \
		+ "items|101000,101200\n" \
		+ "equip|1|0:101000\n" \
		+ "talent|1|2254|t1:5,t2:2\n" \
		+ "seen|ring=3,legendary:cleave=4\n" \
		+ "ach|class:warrior,count:gold5k\n" \
		+ "achat|class:warrior=100,count:gold5k=200\n" \
		+ "stat|kills=10,gold=20\n" \
		+ "beat|1|meadow\n" \
		+ "future|kept|as-is\n" \
		+ "hero|1|1|1|4,5,2,4,0"

var zones := PackedStringArray(["meadow", "cave"])

var game: GameData


func before_all() -> void:
	game = GameData.load_file("res://tests/fixtures/game_data_min.json").value


func _progress() -> SaveProgress:
	return SaveProgress.from_text(SAMPLE)


func test_unedited_save_writes_back_exactly() -> void:
	var p := _progress()
	assert_false(p.is_modified())
	assert_eq(p.to_text(), SAMPLE)


func test_reads_values() -> void:
	var p := _progress()
	assert_eq(p.zones_unlocked(1, zones), 2)
	assert_true(p.is_beaten(1, "meadow"))
	assert_false(p.is_beaten(1, "cave"))
	assert_eq(p.talent_xp(1), 2254)
	assert_eq(p.talent_rank(1, "t2"), 2)
	assert_eq(p.talent_rank(1, "missing"), 0)
	assert_true(p.has_item(101200))
	assert_eq(p.seen_rarity("legendary:cleave"), 4)
	assert_eq(p.seen_rarity("nope"), -1)
	assert_true(p.has_achievement("count:gold5k"))
	assert_eq(p.stat("gold"), 20)
	assert_eq(p.hero_classes(), [1] as Array[int])


func test_setting_same_value_is_not_a_change() -> void:
	var p := _progress()
	p.set_zones_unlocked(1, 2, zones)
	p.set_beaten(1, "meadow", true)
	p.set_item(101000, true)
	p.set_stat("kills", 10)
	assert_false(p.is_modified())


func test_edit_rewrites_only_that_kind_in_place() -> void:
	var p := _progress()
	p.set_stat("gold", 999)
	assert_eq(p.to_text(), SAMPLE.replace("gold=20", "gold=999"))


func test_items_stay_sorted() -> void:
	var p := _progress()
	p.set_item(101100, true)
	p.set_item(101000, false)
	assert_eq(SaveDoc.parse(p.to_text()).first("items")[1], "101100,101200")


func test_talent_ranks() -> void:
	var p := _progress()
	p.set_talent_rank(1, "t2", 0)
	p.set_talent_rank(1, "t3", 4)
	p.set_talent_xp(4, 50)
	var text := p.to_text()
	assert_true(text.contains("talent|1|2254|t1:5,t3:4\n"), text)
	assert_true(text.contains("talent|4|50|\n"), text)


func test_zones_open_is_clamped() -> void:
	var p := _progress()
	p.set_zones_unlocked(1, 99, zones)
	assert_eq(p.zones_unlocked(1, zones), 2)
	p.set_zones_unlocked(1, -5, zones)
	assert_eq(p.zones_unlocked(1, zones), SaveProgress.MIN_ZONES_OPEN)
	assert_eq(SaveDoc.parse(p.to_text()).first("open"), PackedStringArray(["open", "1", "meadow"]))


func test_older_unlock_counts_open_the_zones_added_before_them() -> void:
	var order := PackedStringArray(["elwynn", "duskwood", "wsg", "ungoro", "ab", "feralas", "arena", "sm", "av", "brm",
			"aq", "naxx"])
	var p := SaveProgress.from_text("pick|1\nunlock|1|4\nunlock|4|9\nunlock|5|0\nopen|7|sm\nunlock|7|3\nstat|kills=1")
	assert_eq(p.zones_unlocked(1, order), 5, "4 was up to Arathi Basin, Un'Goro now before it")
	assert_eq(p.zones_unlocked(4, order), 11, "9 was up to Ahn'Qiraj")
	assert_eq(p.zones_unlocked(5, order), 1)
	assert_eq(p.zones_unlocked(7, order), 8, "the furthest of its lines")
	p.set_zones_unlocked(1, 12, order)
	assert_eq(p.to_text(), "pick|1\nopen|1|naxx\nopen|4|aq\nopen|5|elwynn\nopen|7|wsg\nopen|7|sm\nstat|kills=1",
			"open lines in the unlock lines' place; the game takes a class's furthest")


func test_class_without_unlock_record_has_first_zone_open() -> void:
	var p := _progress()
	assert_eq(p.zones_unlocked(4, zones), SaveProgress.MIN_ZONES_OPEN)
	p.set_zones_unlocked(4, 1, zones)
	assert_false(p.is_modified(), "setting the default writes nothing")


func test_bulk_beat() -> void:
	var p := _progress()
	p.set_beaten_for(1, PackedStringArray(["meadow", "cave"]), true)
	assert_eq(SaveDoc.parse(p.to_text()).records_of("beat").size(), 2)
	p.set_beaten_for(1, PackedStringArray(["meadow", "cave"]), false)
	assert_true(SaveDoc.parse(p.to_text()).records_of("beat").is_empty())


## A synthetic tree: rows of talents with the given max ranks, listed out of row order on purpose.
func _tree(ranks_by_row: Array) -> Array:
	var talents := []
	for row in range(ranks_by_row.size() - 1, -1, -1):
		for col in range(ranks_by_row[row].size()):
			talents.append({"id": "r%dc%d" % [row, col], "row": row, "col": col, "ranks": ranks_by_row[row][col]})
	return talents


func test_talent_xp_curve() -> void:
	var cases := {0: 0, 79: 0, 80: 1, 174: 1, 175: 2, 550: 5, 555: 5, 2254: 13, 23204: 50, 23205: 51, 10000000: 51}
	for xp: int in cases:
		assert_eq(SaveProgress.talent_points_for_xp(xp), cases[xp], "xp %d" % xp)
	assert_eq(SaveProgress.FULL_TALENT_XP, 23205)
	assert_eq(SaveProgress.talent_xp_for_points(51), SaveProgress.FULL_TALENT_XP)
	assert_eq(SaveProgress.talent_xp_for_points(1), 80)
	assert_eq(SaveProgress.talent_xp_for_points(99), SaveProgress.FULL_TALENT_XP, "clamped")
	for points in range(SaveProgress.MAX_TALENT_POINTS + 1):
		assert_eq(SaveProgress.talent_points_for_xp(SaveProgress.talent_xp_for_points(points)), points)


func test_points_earned_from_sample_xp() -> void:
	var p := _progress()
	assert_eq(p.talent_points_earned(1), 13, "2254 XP")
	assert_eq(p.talent_points_earned(4), 0, "no record")


func test_max_tree_fills_every_rank_within_budget() -> void:
	var p := SaveProgress.from_text("")
	var tree := _tree([[5, 5], [3, 2], [1]])
	p.max_tree(4, tree)
	assert_eq(p.tree_points_spent(4, tree), 16)
	assert_eq(p.talent_rank(4, "r1c0"), 3)
	assert_eq(p.talent_xp(4), SaveProgress.FULL_TALENT_XP)


func test_max_tree_respects_the_class_budget_top_down() -> void:
	var p := SaveProgress.from_text("")
	p.set_talent_rank(4, "other_tree", SaveProgress.MAX_TALENT_POINTS - 7)
	var tree := _tree([[5, 5], [3]])
	p.max_tree(4, tree)
	assert_eq(p.talent_points_spent(4), SaveProgress.MAX_TALENT_POINTS)
	assert_eq(p.talent_rank(4, "r0c0"), 5, "first row first")
	assert_eq(p.talent_rank(4, "r0c1"), 2)
	assert_eq(p.talent_rank(4, "r1c0"), 0, "later rows get what is left")


func test_max_tree_keeps_higher_talent_xp() -> void:
	var p := _progress()
	p.set_talent_xp(1, SaveProgress.FULL_TALENT_XP + 5)
	p.max_tree(1, _tree([[1]]))
	assert_eq(p.talent_xp(1), SaveProgress.FULL_TALENT_XP + 5)


func _capstones() -> Array:
	return [
		{"id": "bear", "row": 1, "col": 0, "ranks": 1, "excludes": ["cat"]},
		{"id": "cat", "row": 1, "col": 2, "ranks": 1, "excludes": ["bear"]},
		{"id": "base", "row": 0, "col": 0, "ranks": 3, "excludes": []},
	]


func test_max_tree_learns_only_one_of_exclusive_talents() -> void:
	var p := SaveProgress.from_text("")
	var tree := _capstones()
	p.max_tree(11, tree)
	assert_eq(p.talent_rank(11, "bear"), 1, "the first one wins")
	assert_eq(p.talent_rank(11, "cat"), 0)
	assert_eq(p.tree_points_spent(11, tree), 4)


func test_max_tree_keeps_the_exclusive_talent_already_learned() -> void:
	var p := SaveProgress.from_text("talent|11|0|cat:1")
	p.max_tree(11, _capstones())
	assert_eq(p.talent_rank(11, "cat"), 1)
	assert_eq(p.talent_rank(11, "bear"), 0)


func test_set_talent_unlearns_what_it_excludes() -> void:
	var p := SaveProgress.from_text("talent|11|0|bear:1,base:2")
	var tree := _capstones()
	p.set_talent(11, tree[1], 1)
	assert_eq(p.talent_rank(11, "cat"), 1)
	assert_eq(p.talent_rank(11, "bear"), 0)
	assert_eq(p.talent_rank(11, "base"), 2, "others untouched")
	p.set_talent(11, tree[0], 0)
	assert_eq(p.talent_rank(11, "cat"), 1, "unlearning excludes nothing")


func test_reset_tree_and_reset_talents() -> void:
	var p := _progress()
	var tree := [{"id": "t1", "row": 0, "col": 0, "ranks": 5}]
	p.reset_tree(1, tree)
	assert_eq(p.talent_rank(1, "t1"), 0)
	assert_eq(p.talent_rank(1, "t2"), 2, "other talents untouched")
	p.reset_talents(1)
	assert_eq(p.talent_points_spent(1), 0)
	assert_eq(p.talent_xp(1), 2254, "XP is kept")
	assert_true(p.to_text().contains("talent|1|2254|\n"))


func test_reset_talents_without_ranks_is_not_a_change() -> void:
	var p := SaveProgress.from_text("talent|3|10|")
	p.reset_talents(3)
	assert_false(p.is_modified())


func test_win_all_zones_opens_every_zone() -> void:
	var p := _progress()
	p.win_all_zones(4, PackedStringArray(["meadow", "cave"]))
	assert_eq(p.zones_unlocked(4, zones), 2)
	assert_true(p.is_beaten(4, "meadow") and p.is_beaten(4, "cave"))


func test_clear_zones_back_to_first_zone() -> void:
	var p := _progress()
	p.clear_zones(1, PackedStringArray(["meadow", "cave"]))
	assert_eq(p.zones_unlocked(1, zones), SaveProgress.MIN_ZONES_OPEN)
	assert_false(p.is_beaten(1, "meadow"))


func test_set_items_in_bulk() -> void:
	var p := _progress()
	p.set_items(PackedInt32Array([104000, 104010, 101000]), true)
	assert_eq(SaveDoc.parse(p.to_text()).first("items")[1], "101000,101200,104000,104010")
	p.set_items(PackedInt32Array([101000, 101200]), false)
	assert_eq(SaveDoc.parse(p.to_text()).first("items")[1], "104000,104010")


func test_beat_toggle() -> void:
	var p := _progress()
	p.set_beaten(1, "cave", true)
	p.set_beaten(1, "meadow", false)
	var beats := SaveDoc.parse(p.to_text()).records_of("beat")
	assert_eq(beats.size(), 1)
	assert_eq(beats[0], PackedStringArray(["beat", "1", "cave"]))


func test_achievements_keep_timestamps_in_sync() -> void:
	var p := _progress()
	p.set_achievement("zone:meadow", true, 300)
	p.set_achievement("class:warrior", false, 0)
	var doc := SaveDoc.parse(p.to_text())
	assert_eq(doc.first("ach")[1], "count:gold5k,zone:meadow")
	assert_eq(doc.first("achat")[1], "count:gold5k=200,zone:meadow=300")


func test_codex_rarity() -> void:
	var p := _progress()
	p.set_seen_rarity("ring", 4)
	p.set_seen_rarity("legendary:cleave", -1)
	assert_eq(SaveDoc.parse(p.to_text()).first("seen")[1], "ring=4")


func test_bulk_codex_rarity() -> void:
	var p := _progress()
	p.set_seen_rarity_for(PackedStringArray(["ring", "amulet", "legendary:stab"]), 2)
	assert_eq(SaveDoc.parse(p.to_text()).first("seen")[1], "ring=2,legendary:cleave=4,amulet=2,legendary:stab=2")
	p.set_seen_rarity_for(PackedStringArray(["ring", "amulet"]), -1)
	assert_eq(SaveDoc.parse(p.to_text()).first("seen")[1], "legendary:cleave=4,legendary:stab=2")


func test_bulk_achievements_keep_existing_dates() -> void:
	var p := _progress()
	p.set_achievements(PackedStringArray(["count:gold5k", "feat:odds", "zone:cave"]), true, 500)
	var doc := SaveDoc.parse(p.to_text())
	assert_eq(doc.first("achat")[1], "class:warrior=100,count:gold5k=200,feat:odds=500,zone:cave=500")
	p.set_achievements(PackedStringArray(["feat:odds", "class:warrior"]), false, 0)
	assert_eq(SaveDoc.parse(p.to_text()).first("ach")[1], "count:gold5k,zone:cave")


func test_unknown_and_untouched_records_survive_edits() -> void:
	var p := _progress()
	p.fill_all(game, 1000)
	var text := p.to_text()
	for line in ["pick|1|1|1|meadow|Hero|4,5,2,4,0|100,100,100,100", "equip|1|0:101000", "future|kept|as-is"]:
		assert_true(text.contains(line), "kept: " + line)


func test_fill_all() -> void:
	var p := _progress()
	p.fill_all(game, 1000)
	var reread := SaveProgress.from_text(p.to_text())
	for class_id in [1, 4]:
		assert_true(reread.heroes.has(class_id), "hero %d" % class_id)
		assert_eq(reread.zones_unlocked(class_id, game.zone_ids()), 2)
		assert_true(reread.is_beaten(class_id, "meadow") and reread.is_beaten(class_id, "cave"))
		assert_eq(reread.talent_xp(class_id), SaveProgress.FULL_TALENT_XP)
	assert_eq(reread.item_count(), (8 + 1) * 5 + (8 + 2) * 5)
	assert_eq(reread.talent_rank(1, "t1"), 5, "spent ranks are kept")
	assert_eq(reread.seen_rarity("amulet"), SaveProgress.MAX_RARITY)
	assert_eq(reread.seen_rarity("legendary:stab"), SaveProgress.MAX_RARITY)
	assert_true(reread.has_achievement("zone:cave") and reread.has_achievement("class:rogue"))
	assert_true(reread.has_achievement("feat:odds"))
	assert_eq(reread.stat("kills"), 1000000)
	assert_eq(reread.heroes[4][2], "1", "rogue default race is Human")


func test_fill_all_twice_is_stable() -> void:
	var p := _progress()
	p.fill_all(game, 1000)
	var once := p.to_text()
	var again := SaveProgress.from_text(once)
	again.fill_all(game, 2000)
	assert_false(again.is_modified())
	assert_eq(again.to_text(), once)


# ---------------------------------------------------------------- talent specs

const SPEC_SAVE := "talent|1|2254|t1:5,t2:2\n" \
		+ "talent|5|23205|h1:5,h2:1\n" \
		+ "spec|5|1|a:5||\n" \
		+ "spec|5|1|a:5,b:1|h1:5,h2:1|\n" \
		+ "seen|ring=3"


## Two synthetic trees of one class: a1 (row 0, 15 ranks), a2 (row 1, 3 ranks), milestone a3 (row 2, 1 rank),
## a4 (row 3, needs a3), and capstones c1 / c2 (row 6) of tree a; b1 (row 0, 5 ranks) of tree b.
func _spec_trees() -> Array:
	return [
		{"talents": [
			{"id": "a1", "row": 0, "col": 0, "ranks": 15},
			{"id": "a2", "row": 1, "col": 0, "ranks": 3},
			{"id": "a3", "row": 2, "col": 1, "ranks": 1},
			{"id": "a4", "row": 3, "col": 0, "ranks": 5, "requires": "a3"},
			{"id": "c1", "row": 6, "col": 0, "ranks": 1},
			{"id": "c2", "row": 6, "col": 2, "ranks": 1},
		]},
		{"talents": [{"id": "b1", "row": 0, "col": 0, "ranks": 5}]},
		{"talents": []},
	]


func test_spec_lines_round_trip() -> void:
	var text := SPEC_SAVE + "\nspec|9|7|x:1\nspec|x|0\nspec|1\n"
	var p := SaveProgress.from_text(text)
	assert_false(p.is_modified())
	assert_eq(p.to_text(), text)


func test_reads_specs_as_the_game_does() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	assert_true(p.has_specs(5))
	assert_eq(p.lit_spec(5), 1, "the later line replaces the earlier one")
	assert_eq(p.spec_ranks(5, 0), [["a", 5], ["b", 1]])
	assert_eq(p.spec_ranks(5, 1), [["h1", 5], ["h2", 1]], "the lit spec is the talent record")
	assert_eq(p.spec_ranks(5), p.spec_ranks(5, 1))
	assert_eq(p.spec_ranks(5, 2), [])
	assert_eq(p.talent_rank(5, "a", 0), 5)
	assert_eq(p.talent_points_spent(5, 0), 6)


func test_class_without_spec_line_has_spec_1_lit() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	assert_false(p.has_specs(1))
	assert_eq(p.lit_spec(1), 0)
	assert_eq(p.spec_ranks(1, 0), [["t1", 5], ["t2", 2]])
	assert_eq(p.spec_ranks(1, 1), [])
	assert_eq(p.spec_ranks(1, 2), [])


func test_skips_invalid_spec_lines() -> void:
	var p := SaveProgress.from_text("spec|1\nspec|x|0|a:1\nspec|256|0|a:1\nspec|-1|0|a:1\nspec|2|3|a:1\nspec|3|+2\n" \
			+ "spec|4|0|a:1|b:2\nspec|7|02|||c:3")
	for class_id in [1, 2]:
		assert_false(p.has_specs(class_id), "class %d" % class_id)
	assert_eq(p.lit_spec(3), 2, "a u8 may have a plus sign")
	assert_eq(p.spec_ranks(3, 0), [], "missing builds are empty")
	assert_eq(p.spec_ranks(4, 1), [["b", 2]])
	assert_eq(p.spec_ranks(4, 2), [])
	assert_eq(p.lit_spec(7), 2, "and leading zeros")


func test_lit_edits_without_spec_record_add_no_spec_line() -> void:
	var p := _progress()
	p.set_talent_rank(1, "t1", 3)
	p.reset_tree(1, [{"id": "t2"}])
	assert_false(p.has_specs(1))
	assert_eq(SaveDoc.parse(p.to_text()).records_of("spec").size(), 0)


func test_lit_edits_are_mirrored_to_the_lit_build() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	p.set_talent_rank(5, "h2", 0)
	p.set_talent_rank(5, "h3", 2)
	var text := p.to_text()
	assert_true(text.contains("talent|5|23205|h1:5,h3:2\n"), text)
	assert_eq(SaveDoc.parse(text).records_of("spec"), [PackedStringArray(["spec", "5", "1", "a:5,b:1", "h1:5,h3:2", ""])],
			"one line per class, in the first one's place")
	p.reset_talents(5)
	assert_true(p.to_text().contains("talent|5|23205|\nspec|5|1|a:5,b:1||\n"))


func test_editing_another_spec_changes_only_its_build() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	p.set_talent_rank(5, "b", 3, 0)
	p.set_talent_rank(5, "c", 1, 2)
	var text := p.to_text()
	assert_true(text.contains("talent|5|23205|h1:5,h2:1\nspec|5|1|a:5,b:3|h1:5,h2:1|c:1\n"), text)
	p.reset_talents(5, 0)
	assert_true(p.to_text().contains("spec|5|1||h1:5,h2:1|c:1\n"))


func test_editing_another_spec_makes_a_spec_record() -> void:
	var p := _progress()
	p.set_talent_rank(1, "x", 2, 1)
	assert_true(p.has_specs(1))
	assert_eq(p.lit_spec(1), 0)
	var text := p.to_text()
	assert_true(text.contains("talent|1|2254|t1:5,t2:2\nspec|1|0|t1:5,t2:2|x:2|\nseen|"), text)
	assert_eq(SaveProgress.from_text(text).to_text(), text)


func test_setting_a_specs_ranks_unchanged_is_not_a_change() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	p.set_talent_rank(5, "a", 5, 0)
	p.set_spec_ranks(5, 2, [])
	p.set_spec_ranks(1, 2, [])
	p.reset_talents(4, 1)
	assert_false(p.is_modified())
	assert_false(p.has_specs(1) or p.has_specs(4))


func test_switch_makes_the_record_and_lights_the_spec() -> void:
	var p := SaveProgress.from_text("talent|11|23205|a1:5,b1:2\nseen|ring=3")
	assert_true(p.switch_spec(11, 2, _spec_trees()))
	assert_eq(p.lit_spec(11), 2)
	assert_eq(p.talent_points_spent(11), 0, "Spec 3 was empty")
	assert_eq(p.spec_ranks(11, 0), [["a1", 5], ["b1", 2]], "the old talents kept as Spec 1")
	assert_eq(p.to_text(), "talent|11|23205|\nspec|11|2|a1:5,b1:2||\nseen|ring=3")
	assert_true(p.switch_spec(11, 0, _spec_trees()))
	assert_eq(p.to_text(), "talent|11|23205|a1:5,b1:2\nspec|11|0|a1:5,b1:2||\nseen|ring=3")


func test_switch_is_refused_for_the_lit_spec_or_out_of_range() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	for spec in [1, 3, -1]:
		assert_false(p.switch_spec(5, spec, _spec_trees()), "spec %d" % spec)
	assert_false(p.switch_spec(1, 0, _spec_trees()), "Spec 1 is lit without a record")
	assert_false(p.is_modified())
	assert_false(p.has_specs(1))


func test_switch_relearns_the_build_within_the_points() -> void:
	var p := SaveProgress.from_text("talent|11|175|b1:1\nspec|11|0|b1:1|a2:3,a1:4,b1:5|")
	assert_true(p.switch_spec(11, 1, _spec_trees()))
	assert_eq(p.talent_points_earned(11), 2)
	assert_eq(p.spec_ranks(11), [["a1", 2]], "two points, row 1 not open")
	assert_true(p.to_text().contains("talent|11|175|a1:2\nspec|11|1|b1:1|a1:2|"), p.to_text())


func test_switch_drops_rewritten_invalid_lines() -> void:
	var p := SaveProgress.from_text("talent|1|0|\nspec|1|9|x:1\nspec|x\nseen|")
	assert_true(p.switch_spec(1, 1, _spec_trees()))
	assert_eq(p.to_text(), "talent|1|0|\nspec|1|1|||\nseen|")


func test_sanitized_ranks_follow_the_tree_rules() -> void:
	var trees := _spec_trees()
	var all := [["c1", 1], ["c2", 1], ["a4", 5], ["a3", 1], ["a2", 3], ["a1", 20], ["b1", 9], ["zz", 1]]
	assert_eq(SaveProgress.sanitized_ranks(trees, all, 51), [["a1", 15], ["b1", 5], ["a2", 3], ["a3", 1], ["a4", 5]],
			"(row, tree, column) order, max ranks, own talents only; capstones need 30 points below")
	assert_eq(SaveProgress.sanitized_ranks(trees, all, 17), [["a1", 15], ["b1", 2]], "within the points")
	assert_eq(SaveProgress.sanitized_ranks(trees, [["a2", 3]], 51), [], "row 1 needs 5 points below in its tree")
	assert_eq(SaveProgress.sanitized_ranks(trees, [["b1", 5], ["a2", 3]], 51), [["b1", 5]], "not from another tree")
	assert_eq(SaveProgress.sanitized_ranks(trees, [["a1", 5], ["a2", 3], ["a3", 1], ["a4", 2]], 0), [], "no points")
	assert_eq(SaveProgress.sanitized_ranks(trees, [["a1", 15], ["a2", 3], ["a4", 2]], 51), [["a1", 15], ["a2", 3]],
			"a4 needs a3 at full rank")


func test_sanitized_ranks_learn_one_capstone() -> void:
	var trees := [{"talents": [{"id": "low", "row": 0, "col": 0, "ranks": 30}, {"id": "c1", "row": 6, "col": 0, "ranks": 1},
			{"id": "c2", "row": 6, "col": 2, "ranks": 1}]}]
	assert_eq(SaveProgress.sanitized_ranks(trees, [["c2", 1], ["c1", 1], ["low", 30]], 51), [["low", 30], ["c1", 1]])
