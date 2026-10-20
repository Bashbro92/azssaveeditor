extends TestCase
## Game data extracted from the real game. Needs the game executable (Windows or Linux build): set
## AZS_EXE.

var game: GameData


func before_all() -> void:
	var exe := OS.get_environment("AZS_EXE")
	if exe.is_empty():
		skip("set AZS_EXE to the game exe to run")
		return
	var bytes := KeyFinder.read_exe(exe)
	var image := ExeImage.open(bytes.value) if bytes.ok else bytes
	var loaded := GameData.from_exe(image.value) if image.ok else image
	if not loaded.ok:
		skip(loaded.error)
		return
	game = loaded.value


func test_tables() -> void:
	assert_eq(game.classes.size(), 9)
	assert_eq(game.zone_ids().size(), 12)
	assert_eq(game.abilities.size(), 112)
	assert_eq(game.jewels.size(), 22)
	assert_eq(game.amulets.size(), 17)
	assert_eq(game.achievements.size(), 73)
	assert_eq(game.trees_for_class("warrior")[0]["name"], "Arms")
	assert_eq(game.class_by_wow_id(11)["spell_pool"][-1], "shred")
	assert_eq(game.item_name(101010), "Valor Helm")
	assert_eq(game.item_name(104940), "Kingsfall")
	assert_eq(game.item_name(101050), "Field Marshal's Helm", "PvP, as saved")
	assert_eq(game.item_name(101060), "Warlord's Helm", "the same piece in the Horde look")
	assert_eq(game.item_name(101850), "Grand Marshal's Claymore")
	assert_eq(game.item_name(104950), "Grand Marshal's Mageblade")
	assert_eq(game.item_ids_for_class("warrior", 1).size(), 9 * 6)


func test_perks_tabards_and_companion_looks() -> void:
	assert_eq(game.perks.size(), 13)
	assert_eq(game.perks[0], {"id": "rerolls", "name": "Second Thoughts", "icon": "Spell_Nature_TimeStop",
			"costs": [15, 25, 35], "requires": "count:runs10", "requires_perk": ""})
	assert_eq(game.perks[-1]["requires_perk"], "companion")
	assert_eq(game.tabards.size(), 20)
	assert_eq(game.tabards[0]["id"], 90001)
	assert_eq(game.tabards.filter(func(t: Dictionary) -> bool: return t["unlock"] == "").size(), 14, "bought ones")
	assert_eq(game.companion_looks.size(), 13)
	assert_eq([game.companion_looks[0]["id"], game.companion_looks[0]["unlock"]], ["squirrel", ""])
	assert_eq([game.companion_looks[-1]["id"], game.companion_looks[-1]["unlock"]], ["sapphiron", "feat:nou"],
			"0.103.1")


func test_achievements_come_with_icons() -> void:
	var by_key := {}
	for a in game.achievements:
		by_key[a["key"]] = a
		assert_true(a["icon"] != "" and a["description"] != "", "%s is complete" % a["key"])
	assert_eq(by_key["talents:1"]["icon"], "INV_Misc_Book_11")
	assert_eq(by_key["count:kills100k"]["icon"], "INV_Sword_39", "a literal the linker shares")
	assert_eq(by_key["pieces:100"]["description"], "Collect 100 pieces of gear, of any class.")
	assert_eq(by_key["count:bosses100"]["description"], "Slay 100 bosses.")
	assert_eq([by_key["feat:nou"]["name"], by_key["feat:nou"]["icon"], by_key["feat:nou"]["group"]],
			["no u", "Spell_Frost_FrostBolt02", "Feats"], "0.103.1, after the enemy names")


func test_feral_capstones_exclude_each_other() -> void:
	var feral: Array = game.trees_for_class("druid")[1]["talents"]
	var excludes := {}
	for t: Dictionary in feral:
		if t["excludes"]:
			excludes[t["id"]] = t["excludes"]
	assert_eq(excludes, {"leader_of_pack": ["cat_form"], "cat_form": ["leader_of_pack"]})


## Prerequisites are the milestones: a 1-rank talent of the same tree in a lower row.
func test_talent_prerequisites_are_lower_milestones() -> void:
	var required := 0
	for tree in game.talent_trees:
		var by_id := {}
		for t: Dictionary in tree["talents"]:
			by_id[t["id"]] = t
		for t: Dictionary in tree["talents"]:
			if t["requires"] == "":
				continue
			required += 1
			assert_true(by_id.has(t["requires"]), "%s requires %s of its tree" % [t["id"], t["requires"]])
			var needed: Dictionary = by_id.get(t["requires"], {})
			assert_eq(needed.get("ranks"), 1, t["requires"])
			assert_true(int(needed.get("row", 99)) < int(t["row"]), "%s is below %s" % [t["requires"], t["id"]])
	assert_true(required > 0, "some talents have a prerequisite")


## Every real tree fits the talent budget, so "max tree" fills it completely on a fresh class,
## learning one talent of each exclusive pair.
func test_max_tree_fills_every_tree() -> void:
	for tree in game.talent_trees:
		var total := 0
		var learned: Array[String] = []
		for t: Dictionary in tree["talents"]:
			if t["excludes"].any(func(other: String) -> bool: return other in learned):
				continue
			learned.append(t["id"])
			total += int(t["ranks"])
		var p := SaveProgress.from_text("")
		p.max_tree(1, tree["talents"])
		assert_eq(p.talent_points_spent(1), total, tree["name"])
		assert_true(total <= SaveProgress.MAX_TALENT_POINTS, "%s has %d points" % [tree["name"], total])


## A maxed tree is a legal build: the game's sanitizer keeps every rank of it.
func test_maxed_trees_survive_the_sanitizer() -> void:
	for c in game.classes:
		var trees: Array = game.trees_for_class(c["id"])
		for tree: Dictionary in trees:
			var p := SaveProgress.from_text("")
			p.max_tree(1, tree["talents"])
			var kept := SaveProgress.sanitized_ranks(trees, p.spec_ranks(1), SaveProgress.MAX_TALENT_POINTS)
			var total := 0
			for pair: Array in kept:
				total += pair[1]
			assert_eq(total, p.talent_points_spent(1), tree["name"])
