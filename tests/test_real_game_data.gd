extends TestCase
## Game data extracted from the real exe. Needs the game exe: set AZS_EXE.

var game: GameData


func before_all() -> void:
	var exe := OS.get_environment("AZS_EXE")
	if exe.is_empty():
		skip("set AZS_EXE to the game exe to run")
		return
	var bytes := KeyFinder.read_exe(exe)
	var loaded := GameData.from_exe(bytes.value) if bytes.ok else bytes
	if not loaded.ok:
		skip(loaded.error)
		return
	game = loaded.value


func test_tables() -> void:
	assert_eq(game.classes.size(), 9)
	assert_eq(game.zone_ids().size(), 9)
	assert_eq(game.abilities.size(), 112)
	assert_eq(game.jewels.size(), 22)
	assert_eq(game.amulets.size(), 17)
	assert_eq(game.achievements.size(), 66)
	assert_eq(game.trees_for_class("warrior")[0]["name"], "Arms")
	assert_eq(game.class_by_wow_id(11)["spell_pool"][-1], "shred")
	assert_eq(game.item_name(101010), "Valor Helm")
	assert_eq(game.item_name(104940), "Kingsfall")


func test_feral_capstones_exclude_each_other() -> void:
	var feral: Array = game.trees_for_class("druid")[1]["talents"]
	var excludes := {}
	for t: Dictionary in feral:
		if t["excludes"]:
			excludes[t["id"]] = t["excludes"]
	assert_eq(excludes, {"leader_of_pack": ["cat_form"], "cat_form": ["leader_of_pack"]})


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
