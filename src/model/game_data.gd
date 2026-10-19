class_name GameData
extends RefCounted
## Game content the editor needs: classes, zones, talent trees, abilities, jewelry and gear naming.
##
## Read from the user's game executable by GameDataExtractor; tests load the same shape
## from a JSON fixture.

const TREES_PER_CLASS := 3
const GEAR_TIERS := 6  # 0 common … 4 legendary, 5 PvP (0.96.0)
const PVP_TIER := 5
const PVP_HORDE_TIER := 6  ## the id digit of a PvP piece in the Horde look (the game saves 5, shows Horde heroes 6)
const ARMOR_SLOTS := 8
## Armor slot index -> WoW inventory slot (the `slot.N` text keys and `equip` records use these).
const ARMOR_INVENTORY_SLOTS: Array[int] = [0, 2, 4, 5, 6, 7, 8, 9]
const WEAPON_INVENTORY_SLOTS: Array[int] = [15, 16]
## Vanilla tier-set armor type per class id.
const _ARMOR_TYPE := {
	"warrior": "plate", "paladin": "plate", "hunter": "mail", "shaman": "mail",
	"rogue": "leather", "druid": "leather", "priest": "cloth", "mage": "cloth", "warlock": "cloth",
}

var classes: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var talent_trees: Array[Dictionary] = []
var abilities: Dictionary = {}  # id -> ability
var jewels: Array[Dictionary] = []
var amulets: Array[Dictionary] = []
var achievements: Array[Dictionary] = []  # key, name, description, icon, group
var text: Dictionary = {}       # English localisation, key -> string
## WoW class id (as a string) -> the PvP set's English names: {sets: [Alliance, Horde], weapons: [line × 2 +
## faction]}; empty for data from before 0.96.0.
var pvp_gear: Dictionary = {}
## Account perks: id, name, icon, costs (one per rank), requires (achievement key), requires_perk.
var perks: Array[Dictionary] = []
## Tabards: id, name, icon, unlock (the achievement that earns it; "" = bought with perk points), cost.
var tabards: Array[Dictionary] = []
## The pickup companions' looks: id, name, icon, unlock (the achievement that unlocks it; "" = always).
var companion_looks: Array[Dictionary] = []


## Game data read from the user's game executable.
static func from_exe(exe: ExeImage) -> Result:
	var extracted := GameDataExtractor.extract(exe)
	return from_dict(extracted.value) if extracted.ok else extracted


static func load_file(path: String) -> Result:
	if not FileAccess.file_exists(path):
		return Result.failure("game data not found at %s" % path)
	return from_json(FileAccess.get_file_as_string(path))


static func from_json(json_text: String) -> Result:
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return Result.failure("game data is not a JSON object")
	return from_dict(parsed)


static func from_dict(parsed: Dictionary) -> Result:
	for key in ["classes", "zones", "talent_trees", "abilities", "jewels", "amulets", "achievements", "text_en"]:
		if not parsed.has(key):
			return Result.failure("game data is missing '%s'" % key)
	var data := GameData.new()
	data.classes.assign(parsed["classes"])
	data.zones.assign(parsed["zones"])
	data.talent_trees.assign(parsed["talent_trees"])
	data.jewels.assign(parsed["jewels"])
	data.amulets.assign(parsed["amulets"])
	data.achievements.assign(parsed["achievements"])
	data.text = parsed["text_en"]
	data.pvp_gear = parsed.get("pvp_gear", {})
	data.perks.assign(parsed.get("perks", []))
	data.tabards.assign(parsed.get("tabards", []))
	data.companion_looks.assign(parsed.get("companion_looks", []))
	for ability: Dictionary in parsed["abilities"]:
		data.abilities[ability["id"]] = ability
	if data.talent_trees.size() != data.classes.size() * TREES_PER_CLASS:
		return Result.failure("expected %d talent trees, found %d" % [data.classes.size() * TREES_PER_CLASS, data.talent_trees.size()])
	return Result.success(data)


## The class with this WoW class id (as used in save records), or an empty dictionary.
func class_by_wow_id(wow_class_id: int) -> Dictionary:
	for c in classes:
		if int(c["wow_class_id"]) == wow_class_id:
			return c
	return {}


## The three talent trees of a class, in the game's order.
func trees_for_class(class_id: String) -> Array[Dictionary]:
	var trees: Array[Dictionary] = []
	for i in range(classes.size()):
		if classes[i]["id"] == class_id:
			trees.assign(talent_trees.slice(i * TREES_PER_CLASS, (i + 1) * TREES_PER_CLASS))
	return trees


func zone_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for z in zones:
		ids.append(z["id"])
	return ids


## Number of weapon lines a class has (2 for dual weapon lines: main and off hand).
func weapon_lines(class_id: String) -> int:
	return 2 if text.has("weapon.%s.1.0" % class_id) else 1


## Save-file item id of a gear piece; slot 0-7 armor, 8+ weapon lines.
static func item_id(wow_class_id: int, slot: int, tier: int) -> int:
	return 100000 + wow_class_id * 1000 + slot * 100 + tier * 10


## Every gear item id of a class: all armor slots and weapon lines, all tiers (PvP ones as the game saves
## them, in the Alliance look; none without a PvP set).
func item_ids_for_class(class_id: String, wow_class_id: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for slot in range(ARMOR_SLOTS + weapon_lines(class_id)):
		for tier in range(GEAR_TIERS if pvp_gear.has(str(wow_class_id)) else PVP_TIER):
			ids.append(item_id(wow_class_id, slot, tier))
	return ids


## Display name of a gear item id, e.g. "Valor Helm" or "Sulfuras, Hand of Ragnaros".
func item_name(id: int) -> String:
	@warning_ignore("integer_division")
	var c := class_by_wow_id((id / 1000) % 100)
	if c.is_empty():
		return "Unknown item %d" % id
	@warning_ignore("integer_division")
	var slot := (id / 100) % 10
	@warning_ignore("integer_division")
	var tier := (id / 10) % 10
	if tier >= PVP_TIER:
		return _pvp_name(c, slot, tier - PVP_TIER, id)
	if slot >= ARMOR_SLOTS:
		return text.get("weapon.%s.%d.%d" % [c["id"], slot - ARMOR_SLOTS, tier], "Weapon %d" % id)
	var set_name: String = text.get("set.%s.%d" % [c["id"], tier], "")
	var noun: String = text.get("noun.%s.%d" % [_ARMOR_TYPE.get(c["id"], "cloth"), slot], "")
	return ("%s %s" % [set_name, noun]).strip_edges()


## A PvP piece's name in `faction`'s look (0 Alliance, 1 Horde): the set's name before the noun, or the weapon's.
func _pvp_name(c: Dictionary, slot: int, faction: int, id: int) -> String:
	var pvp: Dictionary = pvp_gear.get(str(int(c["wow_class_id"])), {})
	if pvp.is_empty() or faction > 1:
		return "Unknown item %d" % id
	if slot >= ARMOR_SLOTS:
		var weapons: Array = pvp["weapons"]
		var at := (slot - ARMOR_SLOTS) * 2 + faction
		return text.get("weapon.pvp." + weapons[at], weapons[at]) if at < weapons.size() else "Weapon %d" % id
	var set_name: String = pvp["sets"][faction]
	var noun: String = text.get("noun.%s.%d" % [_ARMOR_TYPE.get(c["id"], "cloth"), slot], "")
	return ("%s %s" % [text.get("set.pvp." + set_name, set_name), noun]).strip_edges()


## Icon names used anywhere in the data, for preloading or verification.
func icon_names() -> PackedStringArray:
	var names := {}
	for c in classes:
		names[c["icon"]] = true
	for a: Dictionary in abilities.values():
		names[a["icon"]] = true
	for tree in talent_trees:
		names[tree["icon"]] = true
		for t: Dictionary in tree["talents"]:
			names[t["icon"]] = true
	for j in jewels + amulets:
		names[j["icon"]] = true
	for a in achievements:
		names[a["icon"]] = true
	for row in perks + tabards + companion_looks:
		names[row["icon"]] = true
	var out := PackedStringArray(names.keys())
	out.sort()
	return out
