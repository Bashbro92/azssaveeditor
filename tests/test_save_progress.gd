extends TestCase

## A save as the game writes it (0.100.1 on), in the fixture's zones: every line in the writer's order.
const SAMPLE := "pick|1|1|1|meadow|Hero|4,5,2,4,0|100,100,100,100\n" \
		+ "open|1|cave\n" \
		+ "items|101000,101200\n" \
		+ "equip|1|0:101000\n" \
		+ "look|1|\n" \
		+ "talent|1|2254|t1:5,t2:2\n" \
		+ "seen|legendary:cleave=4,ring=3\n" \
		+ "ach|class:warrior,count:gold5k\n" \
		+ "achat|class:warrior=100,count:gold5k=200\n" \
		+ "stat|kills=10,gold=20,guardians=0,bosses=0,runs=0,wins=0,caches=0,marks=0\n" \
		+ "beat|1|meadow\n" \
		+ "perk|companion:1,rerolls:2\n" \
		+ "tabard|90011,90018\n" \
		+ "pets|rabbit,owl\n" \
		+ "resets|1\n" \
		+ "hero|1|1|1|4,5,2,4,0\n"
const NO_STATS := ",guardians=0,bosses=0,runs=0,wins=0,caches=0,marks=0"

var zones: Array[String] = ["meadow", "cave"]

var game: GameData


func before_all() -> void:
	game = GameData.load_file("res://tests/fixtures/game_data_min.json").value


func _progress() -> SaveProgress:
	return SaveProgress.from_text(SAMPLE, zones)


## The lines of a kind in `text`, each split at "|".
static func _lines(text: String, kind: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for line in text.split("\n", false):
		if line.begins_with(kind + "|"):
			out.append(line.split("|"))
	return out


func test_a_save_the_game_wrote_writes_back_exactly() -> void:
	var p := _progress()
	assert_false(p.is_modified())
	assert_eq(p.to_text(), SAMPLE)


func test_reads_values() -> void:
	var p := _progress()
	assert_eq(p.zones_unlocked(1), 2)
	assert_true(p.is_beaten(1, "meadow"))
	assert_false(p.is_beaten(1, "cave"))
	assert_eq(p.talent_xp(1), 2254)
	assert_eq(p.talent_rank(1, "t2"), 2)
	assert_eq(p.talent_rank(1, "missing"), 0)
	assert_true(p.has_item(101200))
	assert_eq(p.seen_rarity("legendary:cleave"), 4)
	assert_eq(p.seen_rarity("nope"), -1)
	assert_true(p.has_achievement("count:gold5k"))
	assert_eq(p.achieved_at("count:gold5k"), 200)
	assert_eq(p.stat("gold"), 20)
	assert_eq(p.hero_classes(), [1] as Array[int])
	assert_eq(p.perks(), {"companion": 1, "rerolls": 2})
	assert_eq(p.tabards(), [90011, 90018] as Array[int])
	assert_eq(p.companion_looks(), ["rabbit", "owl"] as Array[String])
	assert_eq(p.perk_resets(), 1)
	assert_eq(p.worn(1), {0: 101000})
	assert_eq(p.pick_text(), "1|1|1|meadow|Hero|4,5,2,4,0|100,100,100,100")


func test_setting_same_value_is_not_a_change() -> void:
	var p := _progress()
	p.set_zones_unlocked(1, 2)
	p.set_beaten(1, "meadow", true)
	p.set_item(101000, true)
	p.set_stat("kills", 10)
	p.set_perk_rank("rerolls", 2)
	p.set_tabard(90011, true)
	p.set_companion_looks(["rabbit", "owl"] as Array[String])
	p.set_perk_resets(1)
	assert_false(p.is_modified())


func test_an_edit_changes_only_its_line() -> void:
	var p := _progress()
	p.set_stat("gold", 999)
	assert_eq(p.to_text(), SAMPLE.replace("gold=20", "gold=999"))


func test_unknown_lines_are_dropped_as_the_game_drops_them() -> void:
	var p := SaveProgress.from_text("future|kept|as-is\n" + SAMPLE + "\n|x\n", zones)
	assert_eq(p.to_text(), SAMPLE)


func test_current_unedited_records_are_preserved() -> void:
	var modern := "coopbeat|elwynn\nraces|1:2\nmarks|125\nstars|101000:3\npity|elwynn:2\nglow|1|fiery\n"
	var p := SaveProgress.from_text(modern + "future|dropped\n", zones)
	assert_eq(p.to_text(), modern)


func test_current_marks_and_stars_are_read_and_edited() -> void:
	var p := SaveProgress.from_text("marks|1|125\nmarks|4|4294967295\nstars|101000:3,101010:9\n", zones)
	assert_eq(p.class_marks(1), 125)
	assert_eq(p.class_marks(4), SaveProgress.MAX_CLASS_MARKS)
	assert_eq(p.item_stars(101000), 3)
	assert_eq(p.item_stars(101010), SaveProgress.MAX_ITEM_STARS)
	p.set_class_marks(1, SaveProgress.MAX_CLASS_MARKS)
	p.set_item_stars(101000, SaveProgress.MAX_ITEM_STARS)
	assert_eq(_lines(p.to_text(), "marks"), [
		PackedStringArray(["marks", "1", "4294967295"]),
		PackedStringArray(["marks", "4", "4294967295"]),
	])
	assert_eq(_lines(p.to_text(), "stars"), [PackedStringArray(["stars", "101000:5,101010:5"])])


func test_bulk_marks_and_stars_cover_every_requested_entry() -> void:
	var p := SaveProgress.from_text("", zones)
	p.set_all_class_marks([1, 4] as Array[int])
	p.set_item_stars_for(PackedInt32Array([101000, 101010, 104000]), SaveProgress.MAX_ITEM_STARS)
	assert_eq(p.class_marks(1), SaveProgress.MAX_CLASS_MARKS)
	assert_eq(p.class_marks(4), SaveProgress.MAX_CLASS_MARKS)
	assert_eq(p.item_stars(101000), 5)
	assert_eq(p.item_stars(104000), 5)
	assert_eq(_lines(p.to_text(), "stars")[0][1], "101000:5,101010:5,104000:5")


## A save of an older build, or one an older editor wrote: unlock lines, one beat line per zone, a short stat line,
## unsorted lists, an undated achievement, an unknown line.
func test_an_older_save_comes_out_as_the_game_rewrites_it() -> void:
	var p := SaveProgress.from_text("pick|1|1|1|duskwood|Hero|4,5,2,4,0|100,100,100,100\r\n" \
			+ "unlock|1|2\n" \
			+ "items|101200,101000,101200\n" \
			+ "seen|ring=3,legendary:cleave=4,ring=1\n" \
			+ "ach|count:gold5k,class:warrior\n" \
			+ "achat|class:warrior=100,count:gold5k=0,class:warrior=50\n" \
			+ "stat|gold=20,kills=10,bogus=3,gold=7\n" \
			+ "beat|1|elwynn\n" \
			+ "beat|1|duskwood\n" \
			+ "beat|3|elwynn\n" \
			+ "beat|1|elwynn\n" \
			+ "future|x\n" \
			+ "hero|1|1|1|4,5,2,4,0")
	assert_eq(p.to_text(), "pick|1|1|1|duskwood|Hero|4,5,2,4,0|100,100,100,100\n" \
			+ "open|1|wsg\n" \
			+ "open|3|duskwood\n" \
			+ "items|101000,101200\n" \
			+ "seen|legendary:cleave=4,ring=3\n" \
			+ "ach|class:warrior,count:gold5k\n" \
			+ "achat|class:warrior=50,count:gold5k=0\n" \
			+ "stat|kills=10,gold=20" + NO_STATS + "\n" \
			+ "beat|1|elwynn,duskwood\n" \
			+ "beat|3|elwynn\n" \
			+ "hero|1|1|1|4,5,2,4,0\n")


func test_reads_the_games_beat_lines_one_zone_each() -> void:
	var p := SaveProgress.from_text("beat|4|cave\nbeat|1|cave,meadow\nbeat|1|meadow\nbeat|1|nowhere,cave\n", zones)
	assert_true(p.is_beaten(1, "meadow") and p.is_beaten(1, "cave") and p.is_beaten(4, "cave"))
	assert_false(p.is_beaten(4, "meadow"))
	assert_eq(p.to_text(), "open|1|cave\nopen|4|cave\nbeat|1|meadow,cave\nbeat|4|cave\n",
			"one line a class, by class then zone order; the zone after a beaten one opens (0.102.3)")


func test_each_beaten_zone_opens_the_next_as_the_save_is_read() -> void:
	var p := SaveProgress.from_text("open|1|elwynn\nopen|3|naxx\nbeat|3|elwynn\nbeat|1|ab\nbeat|9|aq\nbeat|11|naxx")
	assert_eq(p.zones_unlocked(1), 6, "locked back to Elwynn Forest by an older build: Feralas, after Arathi, opens")
	assert_eq(p.zones_unlocked(3), 12, "a larger record stays")
	assert_eq(p.zones_unlocked(9), 12, "Gates of Ahn'Qiraj beaten: Naxxramas opens")
	assert_eq(p.zones_unlocked(11), 12, "no more than the twelve zones")
	assert_eq(p.to_text().split("beat|")[0], "open|1|feralas\nopen|3|naxx\nopen|9|naxx\nopen|11|naxx\n",
			"a class without an open record gets one after the others")
	assert_eq(SaveProgress.from_text(p.to_text()).to_text(), p.to_text(), "repaired once, it reads back the same")


func test_the_repair_opens_zones_only_as_the_save_is_read() -> void:
	var p := SaveProgress.from_text("open|1|ab\nbeat|1|ab")
	p.set_zones_unlocked(1, 1)
	assert_eq(p.zones_unlocked(1), 1, "the editor keeps what is set; the game repairs it when it reads the save")
	assert_eq(SaveProgress.from_text(p.to_text()).zones_unlocked(1), 6)


func test_stat_is_written_only_when_one_is_not_zero() -> void:
	var p := SaveProgress.from_text("stat|kills=0,gold=0\n", zones)
	assert_eq(p.to_text(), "")
	p.set_stat("caches", 5)
	assert_eq(p.to_text(), "stat|kills=0,gold=0,guardians=0,bosses=0,runs=0,wins=0,caches=5,marks=0\n")
	p.set_stat("unknown", 5)
	assert_eq(p.stat("unknown"), 0, "only the game's seven")


func test_undated_achievements_write_no_achat() -> void:
	var p := SaveProgress.from_text("ach|b,a\n", zones)
	p.set_achievement("c", true, 0)
	assert_eq(p.to_text(), "ach|a,b,c\n")
	p.set_achievement("d", true, 70)
	assert_eq(p.to_text(), "ach|a,b,c,d\nachat|d=70\n")


func test_an_empty_save_writes_nothing() -> void:
	assert_eq(SaveProgress.from_text("", zones).to_text(), "")
	assert_eq(SaveProgress.from_text("\n\nfuture|x", zones).to_text(), "")


func test_pick_is_sanitized_as_the_game_keeps_it() -> void:
	var p := SaveProgress.from_text("pick|1|1|0|meadow|Ab\npick|6|9|2|nowhere|x1|1,2|50,512,305,147\n", zones)
	assert_eq(p.pick_text(), "1|1|1|meadow|Hero|0,0,0,0,0|100,500,300,145", "the last one, sanitized")
	p = SaveProgress.from_text("pick|11|4|0|cave|  thRALL |1,2,3,4,5\n", zones)
	assert_eq(p.pick_text(), "11|4|0|cave|Thrall|1,2,3,4,5|100,100,100,100")
	p = SaveProgress.from_text("pick|1|1|1|meadow\npick|x|1|1|meadow|Hero\n", zones)
	assert_eq(p.pick_text(), "", "too few fields, or a class that isn't a number")


func test_heroes_are_read_as_the_game_reads_them() -> void:
	var p := SaveProgress.from_text("hero|1|1|0|0,0,0,0,0\nhero|11|1|0|0,0,0,0,0\nhero|6|1|0|0,0,0,0,0\n" \
			+ "hero|4|3|1|1,2,3,4,5\nhero|1|2|5|1,2,3\n", zones)
	assert_eq(p.hero_classes(), [4, 1] as Array[int], "a later record replaces and goes last; bad races skipped")
	assert_eq(p.hero(1).race, 2)
	assert_eq(p.hero(1).gender, 1)
	assert_eq(p.to_text(), "hero|4|3|1|1,2,3,4,5\nhero|1|2|1|0,0,0,0,0\n")


func test_gear_lines_round_trip_in_slot_order() -> void:
	var p := SaveProgress.from_text("equip|1|15:101800,0:101000,19:5\nlook|3|4:100220\nlook|1|4:0\n", zones)
	assert_eq(p.to_text(), "equip|1|0:101000,15:101800\nlook|1|4:0\nequip|3|\nlook|3|4:100220\n")


func test_perks_tabards_companions_and_resets() -> void:
	var p := SaveProgress.from_text("perk|rerolls:2,companion:1,rerolls:3\ntabard|90018,90011,90018\n" \
			+ "pets|rabbit,owl\npets|frog\nresets|2\nresets|1\n", zones)
	assert_eq(p.to_text(), "perk|companion:1,rerolls:2\ntabard|90011,90018\npets|frog\nresets|2\n",
			"a perk twice keeps its lowest rank, the last pets line, the first resets line")
	p.set_perk_rank("rerolls", 0)
	p.set_perk_rank("banish", 3)
	p.set_tabard(90011, false)
	p.set_companion_looks(["", "owl"] as Array[String])
	p.set_perk_resets(0)
	assert_eq(p.to_text(), "perk|banish:3,companion:1\ntabard|90018\npets|owl\n")


func test_items_stay_sorted() -> void:
	var p := _progress()
	p.set_item(101100, true)
	p.set_item(101000, false)
	assert_eq(_lines(p.to_text(), "items"), [PackedStringArray(["items", "101100,101200"])])


func test_talent_ranks() -> void:
	var p := _progress()
	p.set_talent_rank(1, "t2", 0)
	p.set_talent_rank(1, "t3", 4)
	p.set_talent_xp(4, 50)
	var text := p.to_text()
	assert_true(text.contains("talent|1|2254|t1:5,t3:4\ntalent|4|50|\n"), text)


func test_every_talent_record_is_kept_and_the_first_used() -> void:
	var text := "talent|1|80|t1:1\ntalent|1|175|t1:2\n"
	var p := SaveProgress.from_text(text, zones)
	assert_eq(p.talent_xp(1), 80)
	assert_eq(p.to_text(), text)


func test_zones_open_is_clamped() -> void:
	var p := _progress()
	p.set_zones_unlocked(1, 99)
	assert_eq(p.zones_unlocked(1), 2)
	p.set_zones_unlocked(1, -5)
	assert_eq(p.zones_unlocked(1), SaveProgress.MIN_ZONES_OPEN)
	assert_eq(_lines(p.to_text(), "open"), [PackedStringArray(["open", "1", "meadow"])])


func test_older_unlock_counts_open_the_zones_added_before_them() -> void:
	var p := SaveProgress.from_text("unlock|1|4\nunlock|4|9\nunlock|5|0\nopen|7|sm\nunlock|7|3\nopen|8|nowhere\n" \
			+ "stat|kills=1")
	assert_eq(p.zones_unlocked(1), 5, "4 was up to Arathi Basin, Un'Goro now before it")
	assert_eq(p.zones_unlocked(4), 11, "9 was up to Ahn'Qiraj")
	assert_eq(p.zones_unlocked(5), 1)
	assert_eq(p.zones_unlocked(7), 8, "the furthest of its lines")
	p.set_zones_unlocked(1, 12)
	assert_eq(p.to_text(), "open|1|naxx\nopen|4|aq\nopen|5|elwynn\nopen|7|sm\nstat|kills=1,gold=0" + NO_STATS + "\n",
			"one open line a class, in the order the classes came")


func test_class_without_unlock_record_has_first_zone_open() -> void:
	var p := _progress()
	assert_eq(p.zones_unlocked(4), SaveProgress.MIN_ZONES_OPEN)
	p.set_zones_unlocked(4, 1)
	assert_false(p.is_modified(), "setting the default writes nothing")


func test_bulk_beat() -> void:
	var p := _progress()
	p.set_beaten_for(1, zones, true)
	assert_eq(_lines(p.to_text(), "beat"), [PackedStringArray(["beat", "1", "meadow,cave"])])
	p.set_beaten_for(1, zones, false)
	assert_true(_lines(p.to_text(), "beat").is_empty())


func test_heroic_difficulties_round_trip_and_keep_highest() -> void:
	var p := SaveProgress.from_text("hbeat|1|cave:2,meadow:1,cave:5,missing:4\n" \
			+ "hbeat|4|meadow:9,cave:0\nhbeat|6|meadow:3\n", zones)
	assert_eq(p.heroic_level(1, "meadow"), 1)
	assert_eq(p.heroic_level(1, "cave"), 5)
	assert_eq(p.heroic_level(4, "meadow"), SaveProgress.MAX_HEROIC_LEVEL, "values above V are clamped")
	assert_eq(p.heroic_level(4, "cave"), 0, "zero is not stored")
	assert_eq(p.heroic_level(6, "meadow"), 0, "unknown classes are skipped as the game skips them")
	assert_eq(p.to_text(), "hbeat|1|meadow:1,cave:5\nhbeat|4|meadow:5\n")


func test_unlock_and_clear_all_zone_difficulties() -> void:
	var p := _progress()
	p.unlock_all_zone_difficulties(1)
	for zone in zones:
		assert_eq(p.heroic_level(1, zone), SaveProgress.MAX_HEROIC_LEVEL)
	assert_eq(_lines(p.to_text(), "hbeat"), [PackedStringArray(["hbeat", "1", "meadow:5,cave:5"])])
	p.set_heroic_level(1, "cave", 3)
	assert_eq(p.heroic_level(1, "cave"), 3)
	p.clear_zones(1)
	assert_true(_lines(p.to_text(), "hbeat").is_empty())


func test_beat_toggle() -> void:
	var p := _progress()
	p.set_beaten(1, "cave", true)
	p.set_beaten(1, "meadow", false)
	p.set_beaten(1, "nowhere", true)
	assert_eq(_lines(p.to_text(), "beat"), [PackedStringArray(["beat", "1", "cave"])])


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
	var p := SaveProgress.from_text("", zones)
	var tree := _tree([[5, 5], [3, 2], [1]])
	p.max_tree(4, tree)
	assert_eq(p.tree_points_spent(4, tree), 16)
	assert_eq(p.talent_rank(4, "r1c0"), 3)
	assert_eq(p.talent_xp(4), SaveProgress.FULL_TALENT_XP)


func test_max_tree_respects_the_class_budget_top_down() -> void:
	var p := SaveProgress.from_text("", zones)
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
	var p := SaveProgress.from_text("", zones)
	var tree := _capstones()
	p.max_tree(11, tree)
	assert_eq(p.talent_rank(11, "bear"), 1, "the first one wins")
	assert_eq(p.talent_rank(11, "cat"), 0)
	assert_eq(p.tree_points_spent(11, tree), 4)


func test_max_tree_keeps_the_exclusive_talent_already_learned() -> void:
	var p := SaveProgress.from_text("talent|11|0|cat:1", zones)
	p.max_tree(11, _capstones())
	assert_eq(p.talent_rank(11, "cat"), 1)
	assert_eq(p.talent_rank(11, "bear"), 0)


func test_set_talent_unlearns_what_it_excludes() -> void:
	var p := SaveProgress.from_text("talent|11|0|bear:1,base:2", zones)
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
	var p := SaveProgress.from_text("talent|3|10|", zones)
	p.reset_talents(3)
	assert_false(p.is_modified())


func test_win_all_zones_opens_every_zone() -> void:
	var p := _progress()
	p.win_all_zones(4)
	assert_eq(p.zones_unlocked(4), 2)
	assert_true(p.is_beaten(4, "meadow") and p.is_beaten(4, "cave"))


func test_clear_zones_back_to_first_zone() -> void:
	var p := _progress()
	p.clear_zones(1)
	assert_eq(p.zones_unlocked(1), SaveProgress.MIN_ZONES_OPEN)
	assert_false(p.is_beaten(1, "meadow"))


func test_set_items_in_bulk() -> void:
	var p := _progress()
	p.set_items(PackedInt32Array([104000, 104010, 101000]), true)
	assert_eq(_lines(p.to_text(), "items")[0][1], "101000,101200,104000,104010")
	p.set_items(PackedInt32Array([101000, 101200]), false)
	assert_eq(_lines(p.to_text(), "items")[0][1], "104000,104010")


func test_achievements_keep_timestamps_in_sync() -> void:
	var p := _progress()
	p.set_achievement("zone:meadow", true, 300)
	p.set_achievement("class:warrior", false, 0)
	var text := p.to_text()
	assert_eq(_lines(text, "ach")[0][1], "count:gold5k,zone:meadow")
	assert_eq(_lines(text, "achat")[0][1], "count:gold5k=200,zone:meadow=300")


func test_codex_rarity() -> void:
	var p := _progress()
	p.set_seen_rarity("ring", 4)
	p.set_seen_rarity("legendary:cleave", -1)
	assert_eq(_lines(p.to_text(), "seen")[0][1], "ring=4")


func test_bulk_codex_rarity_keeps_the_codex_sorted() -> void:
	var p := _progress()
	p.set_seen_rarity_for(PackedStringArray(["ring", "amulet", "legendary:stab"]), 2)
	assert_eq(_lines(p.to_text(), "seen")[0][1], "amulet=2,legendary:cleave=4,legendary:stab=2,ring=2")
	p.set_seen_rarity_for(PackedStringArray(["ring", "amulet"]), -1)
	assert_eq(_lines(p.to_text(), "seen")[0][1], "legendary:cleave=4,legendary:stab=2")


func test_bulk_achievements_keep_existing_dates() -> void:
	var p := _progress()
	p.set_achievements(PackedStringArray(["count:gold5k", "feat:odds", "zone:cave"]), true, 500)
	assert_eq(_lines(p.to_text(), "achat")[0][1], "class:warrior=100,count:gold5k=200,feat:odds=500,zone:cave=500")
	p.set_achievements(PackedStringArray(["feat:odds", "class:warrior"]), false, 0)
	assert_eq(_lines(p.to_text(), "ach")[0][1], "count:gold5k,zone:cave")


func test_fill_all_keeps_the_other_lines() -> void:
	var p := _progress()
	p.fill_all(game, 1000)
	var text := p.to_text()
	for line in ["pick|1|1|1|meadow|Hero|4,5,2,4,0|100,100,100,100", "equip|1|0:101000", "perk|companion:1,rerolls:2",
			"pets|rabbit,owl", "resets|1"]:
		assert_true(text.contains(line + "\n"), "kept: " + line)


func test_fill_all() -> void:
	var p := _progress()
	p.fill_all(game, 1000)
	var reread := SaveProgress.from_text(p.to_text(), zones)
	for class_id in [1, 4]:
		assert_true(reread.hero_classes().has(class_id), "hero %d" % class_id)
		assert_eq(reread.zones_unlocked(class_id), 2)
		assert_true(reread.is_beaten(class_id, "meadow") and reread.is_beaten(class_id, "cave"))
		assert_eq(reread.heroic_level(class_id, "meadow"), SaveProgress.MAX_HEROIC_LEVEL)
		assert_eq(reread.heroic_level(class_id, "cave"), SaveProgress.MAX_HEROIC_LEVEL)
		assert_eq(reread.talent_xp(class_id), SaveProgress.FULL_TALENT_XP)
		assert_eq(reread.class_marks(class_id), SaveProgress.MAX_CLASS_MARKS)
		for item_id in game.item_ids_for_class("warrior" if class_id == 1 else "rogue", class_id):
			assert_eq(reread.item_stars(item_id), SaveProgress.MAX_ITEM_STARS)
	assert_eq(reread.item_count(), (8 + 1) * 5 + (8 + 2) * 5)
	assert_eq(reread.talent_rank(1, "t1"), 5, "spent ranks are kept")
	assert_eq(reread.seen_rarity("amulet"), SaveProgress.MAX_RARITY)
	assert_eq(reread.seen_rarity("legendary:stab"), SaveProgress.MAX_RARITY)
	assert_true(reread.has_achievement("zone:cave") and reread.has_achievement("class:rogue"))
	assert_true(reread.has_achievement("feat:odds"))
	assert_eq(reread.stat("kills"), 1000000)
	assert_eq(reread.hero(4).race, 3, "a new rogue is a Dwarf, as on a new save")


func test_fill_all_twice_is_stable() -> void:
	var p := _progress()
	p.fill_all(game, 1000)
	var once := p.to_text()
	var again := SaveProgress.from_text(once, zones)
	again.fill_all(game, 2000)
	assert_false(again.is_modified())
	assert_eq(again.to_text(), once)


# ---------------------------------------------------------------- talent specs

## Talent and spec lines as the game writes them.
const SPEC_SAVE := "talent|1|2254|t1:5,t2:2\n" \
		+ "talent|5|23205|h1:5,h2:1\n" \
		+ "spec|5|1|a:5,b:1|h1:5,h2:1|\n" \
		+ "seen|ring=3\n"


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
	var p := SaveProgress.from_text(SPEC_SAVE)
	assert_false(p.is_modified())
	assert_eq(p.to_text(), SPEC_SAVE)


func test_spec_lines_are_written_one_a_class() -> void:
	var p := SaveProgress.from_text("talent|5|23205|h1:5,h2:1\nspec|5|1|a:5||\nspec|9|7|x:1\nspec|x|0\nspec|1\n" \
			+ "spec|5|1|a:5,b:1|h1:5,h2:1\n")
	assert_eq(p.to_text(), "talent|5|23205|h1:5,h2:1\nspec|5|1|a:5,b:1|h1:5,h2:1|\n")


func test_reads_specs_as_the_game_does() -> void:
	var p := SaveProgress.from_text("talent|5|23205|h1:5,h2:1\nspec|5|1|a:5||\nspec|5|1|a:5,b:1|h1:5,h2:1|\n")
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
	assert_true(_lines(p.to_text(), "spec").is_empty())


func test_lit_edits_are_mirrored_to_the_lit_build() -> void:
	var p := SaveProgress.from_text(SPEC_SAVE)
	p.set_talent_rank(5, "h2", 0)
	p.set_talent_rank(5, "h3", 2)
	var text := p.to_text()
	assert_true(text.contains("talent|5|23205|h1:5,h3:2\n"), text)
	assert_eq(_lines(text, "spec"), [PackedStringArray(["spec", "5", "1", "a:5,b:1", "h1:5,h3:2", ""])])
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
	assert_eq(SaveProgress.from_text(text, zones).to_text(), text)


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
	assert_eq(p.to_text(), "talent|11|23205|\nspec|11|2|a1:5,b1:2||\nseen|ring=3\n")
	assert_true(p.switch_spec(11, 0, _spec_trees()))
	assert_eq(p.to_text(), "talent|11|23205|a1:5,b1:2\nspec|11|0|a1:5,b1:2||\nseen|ring=3\n")


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


func test_switch_writes_the_game_lines_only() -> void:
	var p := SaveProgress.from_text("talent|1|0|\nspec|1|9|x:1\nspec|x\nseen|")
	assert_true(p.switch_spec(1, 1, _spec_trees()))
	assert_eq(p.to_text(), "talent|1|0|\nspec|1|1|||\n")


func test_relearn_talents_as_the_game_reads_them() -> void:
	var p := SaveProgress.from_text("talent|11|175|a2:3,a1:4,zz:1\ntalent|3|0|q:1\nspec|11|0|x|a1:9|\n")
	p.relearn_talents(func(c: int) -> Array: return _spec_trees() if c == 11 else [])
	assert_true(p.is_modified())
	assert_eq(p.to_text(), "talent|11|175|a1:2\ntalent|3|0|\nspec|11|0||a1:2|\n")
	var again := SaveProgress.from_text(p.to_text())
	again.relearn_talents(func(c: int) -> Array: return _spec_trees() if c == 11 else [])
	assert_false(again.is_modified(), "a relearned save stays as it is")


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


## A row's choices (0.104.0's companion pick) rule each other out, as capstones do.
func test_sanitized_ranks_learn_one_choice_of_a_row() -> void:
	var trees := [{"talents": [{"id": "low", "row": 0, "col": 0, "ranks": 10},
			{"id": "pick1", "row": 2, "col": 0, "ranks": 3, "exclusive": true},
			{"id": "plain", "row": 2, "col": 1, "ranks": 3},
			{"id": "pick2", "row": 2, "col": 2, "ranks": 3, "exclusive": true}]}]
	assert_eq(SaveProgress.sanitized_ranks(trees, [["pick2", 3], ["plain", 3], ["pick1", 3], ["low", 10]], 51),
			[["low", 10], ["pick1", 3], ["plain", 3]], "the first choice in (row, column) order is kept")


## From 0.104.0 a talent can need one of two others (Legion Gate: either companion) at full rank.
func test_either_prerequisite_opens_a_talent() -> void:
	var trees := [{"talents": [{"id": "low", "row": 0, "col": 0, "ranks": 20},
			{"id": "pick1", "row": 2, "col": 0, "ranks": 3, "exclusive": true},
			{"id": "pick2", "row": 2, "col": 2, "ranks": 3, "exclusive": true},
			{"id": "gate", "row": 4, "col": 1, "ranks": 1, "requires": "pick1", "requires_or": "pick2"}]}]
	assert_eq(SaveProgress.sanitized_ranks(trees, [["low", 20], ["pick2", 3], ["gate", 1]], 51),
			[["low", 20], ["pick2", 3], ["gate", 1]], "the second one does")
	assert_eq(SaveProgress.sanitized_ranks(trees, [["low", 20], ["pick1", 3], ["gate", 1]], 51),
			[["low", 20], ["pick1", 3], ["gate", 1]], "the first one does")
	assert_eq(SaveProgress.sanitized_ranks(trees, [["low", 20], ["pick1", 2], ["gate", 1]], 51),
			[["low", 20], ["pick1", 2]], "only at full rank")


## 0.104.0 rebuilt a tree and "refunded" its points: the reader is unchanged, so a record of the old tree is replayed
## against the new one. Ids the new tree lacks are dropped; ids it kept stay only as far as their new rows allow.
func test_a_rebuilt_tree_is_refunded_as_the_game_reads_it() -> void:
	var new_tree := [{"talents": []}, {"talents": [
		{"id": "kept_a", "row": 0, "col": 2, "ranks": 5},
		{"id": "kept_b", "row": 1, "col": 0, "ranks": 3},
		{"id": "new", "row": 1, "col": 1, "ranks": 5},
		{"id": "kept_c", "row": 3, "col": 3, "ranks": 3}]}, {"talents": []}]
	var p := SaveProgress.from_text("talent|9|%d|kept_a:5,gone_a:5,kept_b:3,gone_b:5,kept_c:5\n" % SaveProgress.FULL_TALENT_XP)
	p.relearn_talents(func(_c: int) -> Array: return new_tree)
	assert_eq(p.to_text(), "talent|9|%d|kept_a:5,kept_b:3\n" % SaveProgress.FULL_TALENT_XP,
			"kept_c's row needs 15 points below it, which the old ids no longer give")
