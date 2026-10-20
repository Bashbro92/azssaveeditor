extends TestCase
## Game data extracted from the real game. Needs the game executable (Windows or Linux build): set
## AZS_EXE.

var game: GameData
var version: String


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
	version = VersionFinder.find_version(bytes.value)


## Whether the game is 0.104.0 or later (the Demonology rework, Demonic Empowerment).
func _demon_army() -> bool:
	var parts := version.split(".")
	return parts.size() == 3 and (parts[0].to_int() > 0 or parts[1].to_int() >= 104)


func test_tables() -> void:
	assert_eq(game.classes.size(), 9)
	assert_eq(game.zone_ids().size(), 12)
	assert_eq(game.abilities.size(), 113 if _demon_army() else 112, "0.104.0 added Demonic Empowerment")
	assert_eq(game.jewels.size(), 22)
	assert_eq(game.amulets.size(), 17)
	assert_eq(game.achievements.size(), 73)
	assert_eq(game.trees_for_class("warrior")[0]["name"], "Arms")
	assert_eq(game.class_by_wow_id(11)["spell_pool"][-1], "shred")
	if _demon_army():
		assert_eq(game.class_by_wow_id(9)["spell_pool"][-1], "demonic_empowerment")
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


## Prerequisites are talents of the same tree in a lower row (until 0.103.1 always a 1-rank milestone; from 0.104.0
## Soul Devourer needs the 5-rank Demonic Familiar, and Legion Gate either companion).
func test_talent_prerequisites_are_lower_in_their_tree() -> void:
	var required := 0
	for tree in game.talent_trees:
		var by_id := {}
		for t: Dictionary in tree["talents"]:
			by_id[t["id"]] = t
		for t: Dictionary in tree["talents"]:
			for id: String in [t["requires"], t["requires_or"]]:
				if id == "":
					continue
				required += 1
				assert_true(by_id.has(id), "%s requires %s of its tree" % [t["id"], id])
				var needed: Dictionary = by_id.get(id, {})
				if not _demon_army():
					assert_eq(needed.get("ranks"), 1, id)
				assert_true(int(needed.get("row", 99)) < int(t["row"]), "%s is below %s" % [id, t["id"]])
			if t["requires"] == "":
				assert_eq(t["requires_or"], "", "%s has a second prerequisite only with a first" % t["id"])
	assert_true(required > 0, "some talents have a prerequisite")


## 0.104.0's Demonology: the companion choice at 10 points, Legion Gate after either companion, and two capstones.
func test_demonology_choices() -> void:
	if not _demon_army():
		return
	var demonology: Array = game.trees_for_class("warlock")[1]["talents"]
	var by_id := {}
	for t: Dictionary in demonology:
		by_id[t["id"]] = t
	assert_eq(demonology.size(), 14)
	assert_eq(by_id["soul_devourer"]["excludes"], ["soul_link"])
	assert_eq(by_id["soul_link"]["excludes"], ["soul_devourer"])
	assert_eq(by_id["pact_of_the_annihilan"]["excludes"], ["butcher"])
	assert_eq([by_id["legion_gate"]["requires"], by_id["legion_gate"]["requires_or"]], ["soul_devourer", "soul_link"])
	var trees: Array = game.trees_for_class("warlock")
	var p := SaveProgress.from_text("")
	p.max_tree(9, demonology)
	var kept := SaveProgress.sanitized_ranks(trees, p.spec_ranks(9), SaveProgress.MAX_TALENT_POINTS)
	assert_eq(kept.size(), p.spec_ranks(9).size(), "a maxed Demonology is legal")
	assert_eq(p.talent_rank(9, "soul_link") + p.talent_rank(9, "butcher"), 0, "one companion, one capstone")


## A warlock's 0.103.1 Demonology record (43 points) as 0.104.0 reads it: its points are refunded but for the talents
## the new tree kept, as far as their new rows allow. The same record reads unchanged with 0.103.1.
func test_old_demonology_points_are_refunded() -> void:
	const OLD := "demonic_embrace:5,fel_intellect:5,fel_stamina:3,imp_health_funnel:5,summon_imp:1,unholy_power:5," \
			+ "imp_succubus:3,master_demonologist:5,demonic_pact:1,demonic_knowledge:3,imp_enslave:3,demonic_sacrifice:3,felguard:1"
	var p := SaveProgress.from_text("talent|9|%d|%s\n" % [SaveProgress.FULL_TALENT_XP, OLD])
	p.relearn_talents(func(c: int) -> Array: return game.trees_for_class(game.class_by_wow_id(c).get("id", "")))
	if _demon_army():
		assert_eq(p.spec_ranks(9), [["demonic_embrace", 5], ["fel_stamina", 3], ["unholy_power", 5]])
	else:
		assert_eq(p.talent_points_spent(9), 43)


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
