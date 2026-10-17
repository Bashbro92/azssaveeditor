extends TestCase
## Uses a small synthetic fixture; the real exe's data is checked in test_real_game_data.gd.

const FIXTURE := "res://tests/fixtures/game_data_min.json"

var data: GameData


func before_all() -> void:
	data = GameData.load_file(FIXTURE).value


func test_loads_fixture() -> void:
	assert_ok(GameData.load_file(FIXTURE))
	assert_eq(data.classes.size(), 2)
	assert_eq(data.abilities["cleave"]["name"], "Cleave")


func test_missing_file_fails() -> void:
	assert_failed(GameData.load_file("res://does/not/exist.json"))


func test_rejects_incomplete_json() -> void:
	assert_failed(GameData.from_json("[]"))
	assert_failed(GameData.from_json("{\"classes\": []}"))


func test_rejects_wrong_tree_count() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	parsed["talent_trees"].pop_back()
	assert_failed(GameData.from_json(JSON.stringify(parsed)))


func test_class_by_wow_id() -> void:
	assert_eq(data.class_by_wow_id(4)["id"], "rogue")
	assert_true(data.class_by_wow_id(99).is_empty())


func test_trees_for_class() -> void:
	var trees := data.trees_for_class("rogue")
	assert_eq(trees.size(), 3)
	assert_eq(trees[0]["name"], "B1")
	assert_true(data.trees_for_class("nobody").is_empty())


func test_item_id_scheme() -> void:
	assert_eq(GameData.item_id(1, 0, 0), 101000)
	assert_eq(GameData.item_id(1, 1, 1), 101110)
	assert_eq(GameData.item_id(11, 8, 4), 111840)


func test_item_ids_include_weapon_lines() -> void:
	assert_eq(data.item_ids_for_class("warrior", 1).size(), (8 + 1) * 5)
	assert_eq(data.item_ids_for_class("rogue", 4).size(), (8 + 2) * 5)


func test_item_names() -> void:
	assert_eq(data.item_name(101010), "Valor Helm")
	assert_eq(data.item_name(101840), "Big Sword")
	assert_eq(data.item_name(104900), "Offhand Dagger")
	assert_eq(data.item_name(199000), "Unknown item 199000")


func test_pvp_pieces_are_named_by_faction() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	parsed["pvp_gear"] = {"1": {"sets": ["Field Marshal's", "Warlord's"],
			"weapons": ["Grand Marshal's Claymore", "High Warlord's Greatsword"]}}
	var pvp: GameData = GameData.from_dict(parsed).value
	assert_eq(pvp.item_name(101050), "Field Marshal's Helm")
	assert_eq(pvp.item_name(101060), "Warlord's Helm")
	assert_eq(pvp.item_name(101860), "High Warlord's Greatsword")
	assert_eq(pvp.item_name(101870), "Unknown item 101870")
	assert_eq(pvp.item_ids_for_class("warrior", 1).size(), (8 + 1) * 6, "with the PvP tier")
	assert_eq(pvp.item_ids_for_class("rogue", 4).size(), (8 + 2) * 5, "no PvP set here")


func test_icon_names_are_unique_and_sorted() -> void:
	var names := data.icon_names()
	assert_true(names.has("Talent_1") and names.has("Icon_Amulet") and names.has("Tree_B3") and names.has("Icon_Odds"))
	var sorted := names.duplicate()
	sorted.sort()
	assert_eq(names, sorted)

