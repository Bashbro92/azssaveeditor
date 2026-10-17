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
