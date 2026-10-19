class_name GameDataExtractor
extends RefCounted
## Reads the game content the editor needs straight from the user's game executable (Windows or
## Linux build), in the shape GameData.from_dict takes.
##
## Tables are found by content (a known string in their first row), not by fixed offsets, so this
## survives rebuilds as long as the row layouts don't change. Each row is a run of static Rust
## values; the offsets below are where each field sits in a row.

const ZONE_ROW := 240  # from 0.96.0; the row starts 8 bytes before the id
const BOSS_ROW := 88
const ABILITY_ROW := 120
const CLASS_ROW := 144
const TREE_ROW := 64
const TREE_CLASS_HEADER := 8  # sits between each class's three trees
const TALENT_ROW := 104
const JEWEL_ROW := 72
const AMULET_ROW := 80
const STR := 16  # size of a `&str`
const PVP_ROW := 0x78
const PVP_WEAPON := 0x30
const PERK_ROW := 0x78
const TABARD_ROW := 0x40
const COMPANION_LOOK_ROW := 0x60

## Keys the game builds in code rather than storing as text, by achievement name.
const CODE_KEYS := {
	"Fully Talented": "talents:1", "Master of All": "talents:9",
	"Collector": "pieces:25", "Hoarder": "pieces:100", "Curator": "pieces:250",
	"The Whole Armory": "pieces:all", "Legendary": "legendaryset",
	"Jeweler's Eye": "codex:50", "Every Bauble": "codex:100",
}
const PIECES_TEXT := "Collect {n} pieces of gear, of any class."
const TALENT_TEXTS: Array[String] = [
	"Earn all {n} talent points with one class.", "Earn all {n} talent points with every class.",
]
## The achievement builder's first literals: the code that loads them builds every fixed achievement.
const ACHIEVEMENTS_START := "Fully TalentedEarn all {n}"
const ACHIEVEMENTS_CODE_SPAN := 0x8000  # the builder is ~14 KB of code
const ZONE_ICON := "INV_Misc_Map_01"
const FIRST_ZONE_ICON := "INV_Misc_Bandana_03"  ## the zone achievement icon table's first entry (Elwynn)
## The zone "{class} of the Scarab Wall" is about: the game names Ahn'Qiraj's row and C'Thun even with
## zones after it (0.96.0's achievement builder).
const CLASSLAST_ZONE := "aq"

var _exe: ExeImage


## Everything GameData needs, or a failure naming the table that wasn't found.
static func extract(exe: ExeImage) -> Result:
	var extractor := GameDataExtractor.new()
	extractor._exe = exe
	return extractor._extract_all()


func _extract_all() -> Result:
	var text := _texts()
	if text.is_empty():
		return Result.failure("localisation text not found in the exe")
	var data := {"text_en": text}
	var tables := {
		"zones": _zones, "classes": _classes, "abilities": _abilities, "jewels": _jewels,
		"amulets": _amulets,
	}
	for key: String in tables:
		var rows: Array = tables[key].call()
		if rows.is_empty():
			return Result.failure("%s not found in the exe (different game build?)" % key)
		data[key] = rows
	data["talent_trees"] = _talent_trees(data["classes"].size() * GameData.TREES_PER_CLASS)
	data["pvp_gear"] = _pvp_gear()
	data["perks"] = _perks()
	data["tabards"] = _tabards()
	data["companion_looks"] = _companion_looks()
	var achievements := _achievements(text, data["classes"], data["zones"])
	if achievements.is_empty():
		return Result.failure("achievements not found in the exe (different game build?)")
	data["achievements"] = achievements
	return Result.success(data)


# ---------------------------------------------------------------- tables

func _zones() -> Array:
	var out := []
	for o in _rows("Elwynn Forest", ZONE_ROW, [0, 16, 160]):
		var bosses := []
		var b := _exe.slice_at(o + 128)
		for i in range(b[1] if b[0] != -1 else 0):
			var row := b[0] + i * BOSS_ROW
			bosses.append({"name": _exe.str_at(row), "final": _exe.u8(row + 84) == 1})
		out.append({"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "bosses": bosses})
	return out


## The PvP set's names per class (0x78-byte rows, by WoW class id at +0x70; 0.96.0): WoW class id ->
## {sets: [Alliance, Horde], weapons: [line × 2 + faction]} (set names at +0x00/+0x10, weapons at +0x20
## as 0x30-byte {u32 look, &str name} pairs).
func _pvp_gear() -> Dictionary:
	var is_row := func(r: int) -> bool: return _has_strs(r, [0, 16]) and _exe.u32(r + 0x70) >= 1 \
			and _exe.u32(r + 0x70) <= 11 and _exe.slice_at(r + 0x20)[0] != -1
	var o := _anchor_row("Field Marshal's", 0, func(r: int) -> bool: return is_row.call(r) and _exe.u32(r + 0x70) == 1)
	var out := {}
	while o != -1 and is_row.call(o):
		var weapons := []
		var w := _exe.slice_at(o + 0x20)
		for i in range(w[1]):
			var r: int = w[0] + i * PVP_WEAPON
			weapons.append_array([_exe.str_at(r + 8), _exe.str_at(r + 0x20)])
		out[str(_exe.u32(o + 0x70))] = {"sets": [_exe.str_at(o), _exe.str_at(o + 16)], "weapons": weapons}
		o += PVP_ROW
	return out


## The account perks (0x78-byte rows): id +0, name +16, icon +32, u32 cost per rank +48, the achievement that
## unlocks them +80 and the perk they need first +96.
func _perks() -> Array:
	var is_perk := func(r: int) -> bool: return _has_strs(r, [0, 16, 32]) and _exe.slice_at(r + 48)[0] != -1
	var o := _anchor_row("rerolls", 0, is_perk)
	var out := []
	while o != -1 and is_perk.call(o):
		var costs := []
		var c := _exe.slice_at(o + 48)
		for i in range(c[1]):
			costs.append(_exe.u32(c[0] + 4 * i))
		out.append({"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "icon": _exe.str_at(o + 32), "costs": costs,
				"requires": _str_or_empty(o + 80), "requires_perk": _str_or_empty(o + 96)})
		o += PERK_ROW
	return out


## The tabards (0x40-byte rows): name +0, icon +16, the achievement that earns it +32 ("" = bought with perk points),
## u32 id +48 (90001-90099) and cost +56.
func _tabards() -> Array:
	var is_tabard := func(r: int) -> bool: return _has_strs(r, [0, 16]) and _str_or_empty(r + 32) != null \
			and _exe.u32(r + 48) > 90000 and _exe.u32(r + 48) < 90100
	var o := _anchor_row("Stormwind Tabard", 0, is_tabard)
	if o == -1:
		return []
	while is_tabard.call(o - TABARD_ROW):
		o -= TABARD_ROW
	var out := []
	while is_tabard.call(o):
		out.append({"id": _exe.u32(o + 48), "name": _exe.str_at(o), "icon": _exe.str_at(o + 16),
				"unlock": _str_or_empty(o + 32), "cost": _exe.u32(o + 56)})
		o += TABARD_ROW
	return out


## The pickup companions' looks (0x60-byte rows): id +0, name +16, model folder +32, icon +48, the achievement that
## unlocks it +64 ("" = always), creature display +80 and entry +88 (9001-9999).
func _companion_looks() -> Array:
	var is_look := func(r: int) -> bool: return _has_strs(r, [0, 16, 32, 48]) and _str_or_empty(r + 64) != null \
			and _exe.u32(r + 80) > 0 and _exe.u32(r + 88) > 9000 and _exe.u32(r + 88) < 10000
	var o := _anchor_row("squirrel", 0, is_look)
	var out := []
	while o != -1 and is_look.call(o):
		out.append({"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "icon": _exe.str_at(o + 48),
				"unlock": _str_or_empty(o + 64)})
		o += COMPANION_LOOK_ROW
	return out


func _classes() -> Array:
	var out := []
	var is_warrior := func(o: int) -> bool: return _exe.str_at(o + 48) == "cleave"
	for o in _rows("Warrior", CLASS_ROW, [0, 48, 64], is_warrior):
		out.append({
			"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "spell_pool": _str_list(o + 32),
			"starting_spell": _exe.str_at(o + 48), "icon": _exe.str_at(o + 80),
			"wow_class_id": _exe.u8(o + 124),
		})
	return out


func _abilities() -> Array:
	return _named_rows("Cleave", ABILITY_ROW, [0, 16, 32])


func _jewels() -> Array:
	return _named_rows("Band of Accuria", JEWEL_ROW, [0, 16, 48])


func _amulets() -> Array:
	return _named_rows("Mark of Fordring", AMULET_ROW, [0, 16, 32])


## Rows of (id, name, icon) at +0, +16, +32.
func _named_rows(anchor: String, stride: int, required: Array[int]) -> Array:
	var out := []
	for o in _rows(anchor, stride, required):
		out.append({"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "icon": _exe.str_at(o + 32)})
	return out


func _talent_trees(count: int) -> Array:
	var start := _anchor_row("WarriorArms", 16)
	var trees := []
	if start == -1:
		return trees
	var o := start
	var limit := start + count * (TREE_ROW + TREE_CLASS_HEADER) + TREE_ROW
	while trees.size() < count and o < limit:
		if _has_strs(o, [0, 16, 32]):
			var talents := []
			var t := _exe.slice_at(o + 48)
			for i in range(t[1] if t[0] != -1 else 0):
				talents.append(_talent(t[0] + i * TALENT_ROW))
			trees.append({"name": _exe.str_at(o), "icon": _exe.str_at(o + 32), "talents": link_exclusions(talents)})
			o += TREE_ROW
		else:
			o += TREE_CLASS_HEADER
	return trees


func _talent(o: int) -> Dictionary:
	var packed := _exe.u32(o + 96)
	var description: Variant = _exe.str_at(o + 64)
	var requires: Variant = _exe.str_at(o + 80)
	return {
		"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "icon": _exe.str_at(o + 32),
		"description": description if description != null else "", "requires": requires if requires != null else "",
		"row": packed & 0xFF, "col": (packed >> 8) & 0xFF, "ranks": (packed >> 16) & 0xFF,
	}


## The embedded English localisation object (a flat JSON object, keys in the game's order).
func _texts() -> Dictionary:
	var key := _exe.find("\"game.title\"".to_ascii_buffer())
	if key == -1:
		return {}
	var start := _exe.bytes.rfind(0x7B, key)  # "{"
	var end := _exe.find("\n}".to_ascii_buffer(), key)
	if start == -1 or end == -1:
		return {}
	var parsed: Variant = JSON.parse_string(_exe.bytes.slice(start, end + 2).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## The fixed achievements from the strings their builder loads, plus the templated ones.
func _achievements(text: Dictionary, classes: Array, zones: Array) -> Array:
	var keys: Array = text.keys()
	var first := keys.find("Fully Talented")
	var last := keys.find("Jan")
	var start := _exe.find(ACHIEVEMENTS_START.to_ascii_buffer())
	if start == -1 or first == -1 or last <= first:
		return []
	var refs := _exe.lea_refs(start)
	if refs.is_empty():
		return []
	var block: Array[String] = []
	block.assign(keys.slice(first, last))
	block.append_array(TALENT_TEXTS)
	var fixed := assemble_achievements(_exe.lea_strings(refs[0], ACHIEVEMENTS_CODE_SPAN), block)
	return fixed + templated_achievements(classes, zones, _zone_icons(zones.size()))


# ---------------------------------------------------------------- pure helpers (unit-tested)

## Sets `excludes` (talent ids) on talents whose description says another talent of the tree
## can't be learned with them, e.g. the two Feral capstones.
static func link_exclusions(tree: Array) -> Array:
	var by_name := {}
	for t: Dictionary in tree:
		by_name[t["name"]] = t["id"]
	var pattern := RegEx.create_from_string("You can't also learn (.+?)\\.")
	for t: Dictionary in tree:
		var excludes: Array[String] = []
		for m in pattern.search_all(t.get("description", "")):
			if by_name.has(m.get_string(1)):
				excludes.append(by_name[m.get_string(1)])
		t["excludes"] = excludes
	return tree


## Builds the fixed achievements from the strings their builder loads, in code order. The builder
## loads each achievement's name, then its description, and its key and icon either right after or
## in a later run of (key, icon) pairs; so names open achievements in order, a description belongs
## to the latest name, and keys and icons go to the first achievement still without one. `block`
## holds every fixed achievement's name and description (names don't end in a full stop); a name
## seen again and anything left over after the builder are ignored.
static func assemble_achievements(strings: PackedStringArray, block: Array[String]) -> Array:
	var names := {}
	var descriptions := {}
	for entry in block:
		if entry.ends_with("."):
			descriptions[entry] = true
		else:
			names[entry] = true
	var key_pattern := RegEx.create_from_string("^(feat|count):[a-z0-9]+$")
	var icon_pattern := RegEx.create_from_string("^[A-Z][A-Za-z0-9]*_[A-Za-z0-9_]+$")
	var out := []
	for s in strings:
		if names.has(s):
			names.erase(s)
			out.append({"name": s})
		elif out.is_empty():
			continue
		elif descriptions.has(s):
			out[-1].get_or_add("description", s)
		elif key_pattern.search(s):
			var owner: Variant = _first_without(out, "key", true)
			if owner:
				owner["key"] = s
		elif icon_pattern.search(s):
			var owner: Variant = _first_without(out, "icon", false)
			if owner:
				owner["icon"] = s
	for a: Dictionary in out:
		a.get_or_add("key", CODE_KEYS.get(a["name"], ""))
		a.get_or_add("icon", "")
		var key: String = a["key"]
		var description: String = a.get("description", "")
		if key.begins_with("pieces:") and key != "pieces:all":
			description = PIECES_TEXT
		a["description"] = description.replace("{n}", key.get_slice(":", 1) if key.begins_with("pieces:") \
				else str(SaveProgress.MAX_TALENT_POINTS))
		a["group"] = achievement_group(key)
	return out.filter(func(a: Dictionary) -> bool: return a["key"] != "")


## The first achievement without `field` (skipping those whose key is built in code, for keys).
static func _first_without(achievements: Array, field: String, skip_code_keys: bool) -> Variant:
	for a: Dictionary in achievements:
		if not a.has(field) and not (skip_code_keys and CODE_KEYS.has(a["name"])):
			return a
	return null


## The zone achievements' icons, one per zone in order: a table of &str whose first entry is the Elwynn one (each
## the zone's final boss: VanCleef's bandana … C'Thun's trinket). Empty if the exe doesn't have it.
func _zone_icons(count: int) -> Array[String]:
	var out: Array[String] = []
	var at := _exe.find(FIRST_ZONE_ICON.to_ascii_buffer())
	if at == -1:
		return out
	for table in _exe.pointers_to(at):
		out.clear()
		for i in range(count):
			var icon: Variant = _exe.str_at(table + 16 * i)
			if icon == null:
				break
			out.append(icon)
		if out.size() == count:
			return out
	out.clear()
	return out


## The per-class and per-zone achievements the game generates from templates; `zone_icons` (one per zone)
## replaces the generic map icon when given.
static func templated_achievements(classes: Array, zones: Array, zone_icons: Array[String] = []) -> Array:
	var out := []
	var last: Dictionary = zones[-1]
	for z: Dictionary in zones:
		if z["id"] == CLASSLAST_ZONE:
			last = z
	var last_final := _final_boss(last)
	for c: Dictionary in classes:
		out.append({"key": "class:" + c["id"], "name": "%s Victorious" % c["name"],
				"description": "Win a run with a %s." % c["name"], "icon": c["icon"]})
		out.append({"key": "classlast:" + c["id"], "name": "%s of the Scarab Wall" % c["name"],
				"description": "Defeat %s at %s with a %s." % [last_final, last["name"], c["name"]], "icon": c["icon"]})
	for nine in [false, true]:  # every zone's, then every zone's champion, as the game's Achievements list orders them
		for i in range(zones.size()):
			var z: Dictionary = zones[i]
			var final := _final_boss(z)
			var icon: String = zone_icons[i] if i < zone_icons.size() else ZONE_ICON
			if nine:
				out.append({"key": "zone9:" + z["id"], "name": "Champion of %s" % z["name"],
						"description": "Defeat %s in %s with all nine classes." % [final, z["name"]], "icon": icon})
			else:
				out.append({"key": "zone:" + z["id"], "name": z["name"],
						"description": "Defeat %s in %s with any class." % [final, z["name"]], "icon": icon})
	for a: Dictionary in out:
		a["group"] = achievement_group(a["key"])
	return out


static func achievement_group(key: String) -> String:
	const GROUPS := {"count": "Counts", "feat": "Feats", "zone": "Zones", "zone9": "Zones",
			"class": "Classes", "classlast": "Classes", "talents": "Classes"}
	return GROUPS.get(key.get_slice(":", 0), "Collection")


static func _final_boss(zone: Dictionary) -> String:
	for b: Dictionary in zone.get("bosses", []):
		if b["final"]:
			return b["name"]
	return "the final boss"


# ---------------------------------------------------------------- rows

## Offset of the row whose `&str` at `field` is exactly `text` (and passes `check`), or -1.
func _anchor_row(text: String, field: int, check: Callable = Callable()) -> int:
	var raw := text.to_utf8_buffer()
	var at := _exe.find(raw)
	while at != -1:
		for x in _exe.pointers_to(at):
			if _exe.u64(x + 8) == raw.size() and _exe.str_at(x) == text \
					and (check.is_null() or check.call(x - field)):
				return x - field
		at = _exe.find(raw, at + 1)
	return -1


## Offsets of consecutive rows from the anchor row on, while each has strings at `required`.
func _rows(anchor: String, stride: int, required: Array[int], check: Callable = Callable()) -> Array[int]:
	var out: Array[int] = []
	var o := _anchor_row(anchor, 16, check)
	while o != -1 and _has_strs(o, required):
		out.append(o)
		o += stride
	return out


## A `&str` at offset o, "" for an empty one, or null if it isn't one.
func _str_or_empty(o: int) -> Variant:
	return "" if _exe.u64(o + 8) == 0 else _exe.str_at(o)


func _has_strs(o: int, fields: Array[int]) -> bool:
	for f in fields:
		if _exe.str_at(o + f) == null:
			return false
	return true


## A slice of `&str` at offset o, as strings.
func _str_list(o: int) -> Array[String]:
	var out: Array[String] = []
	var s := _exe.slice_at(o)
	for i in range(s[1] if s[0] != -1 else 0):
		out.append(_exe.str_at(s[0] + i * STR))
	return out
