class_name GameDataExtractor
extends RefCounted
## Reads the game content the editor needs straight from the user's AzerothSurvivors.exe, in the
## shape GameData.from_dict takes.
##
## Tables are found by content (a known string in their first row), not by fixed offsets, so this
## survives rebuilds as long as the row layouts don't change. Each row is a run of static Rust
## values; the offsets below are where each field sits in a row.

const ZONE_ROW := 184
const BOSS_ROW := 88
const ABILITY_ROW := 120
const CLASS_ROW := 144
const TREE_ROW := 64
const TREE_CLASS_HEADER := 8  # sits between each class's three trees
const TALENT_ROW := 104
const JEWEL_ROW := 72
const AMULET_ROW := 80
const STR := 16  # size of a `&str`

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
const ACHIEVEMENTS_START := "Fully TalentedEarn all {n}"
const ACHIEVEMENTS_END := "INV_BannerPVP_01"
const ZONE_ICON := "INV_Misc_Map_01"
## Stands for the binary bytes between the achievement builder's literals.
const GAP := "\u0001"

var _exe: ExeImage


## Everything GameData needs, or a failure naming the table that wasn't found.
static func extract(exe: PackedByteArray) -> Result:
	var opened := ExeImage.open(exe)
	if not opened.ok:
		return opened
	var extractor := GameDataExtractor.new()
	extractor._exe = opened.value
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
	var achievements := _achievements(text, data["classes"], data["zones"])
	if achievements.is_empty():
		return Result.failure("achievements not found in the exe (different game build?)")
	data["achievements"] = achievements
	return Result.success(data)


# ---------------------------------------------------------------- tables

func _zones() -> Array:
	var out := []
	for o in _rows("Elwynn Forest", ZONE_ROW, [0, 16, 112]):
		var bosses := []
		var b := _exe.slice_at(o + 80)
		for i in range(b[1] if b[0] != -1 else 0):
			var row := b[0] + i * BOSS_ROW
			bosses.append({"name": _exe.str_at(row), "final": _exe.u8(row + 84) == 1})
		out.append({"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "bosses": bosses})
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
	return {
		"id": _exe.str_at(o), "name": _exe.str_at(o + 16), "icon": _exe.str_at(o + 32),
		"description": description if description != null else "",
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


func _achievements(text: Dictionary, classes: Array, zones: Array) -> Array:
	var start := _exe.find(ACHIEVEMENTS_START.to_ascii_buffer())
	var end := _exe.find(ACHIEVEMENTS_END.to_ascii_buffer(), maxi(start, 0))
	var keys: Array = text.keys()
	var first := keys.find("Fully Talented")
	var last := keys.find("Jan")
	if start == -1 or end == -1 or first == -1 or last <= first:
		return []
	var block: Array[String] = []
	block.assign(keys.slice(first, last))
	block.append_array(TALENT_TEXTS)
	var fixed := parse_achievement_run(literal_run(_exe.bytes.slice(start, end + ACHIEVEMENTS_END.length())), block)
	return fixed + templated_achievements(classes, zones)


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


## Raw bytes as text, every run of non-printable bytes turned into one GAP.
static func literal_run(raw: PackedByteArray) -> String:
	var out := PackedByteArray()
	for byte in raw:
		if byte >= 0x20 and byte <= 0x7E:
			out.append(byte)
		elif out.is_empty() or out[-1] != GAP.unicode_at(0):
			out.append(GAP.unicode_at(0))
	return out.get_string_from_ascii()


## Splits the achievement builder's concatenated literals (name, description, key, icon, …; GAP
## marks binary bytes) into achievements, using `block` (the known names and descriptions) to find
## the boundaries. Names are the block entries that don't end in a full stop.
static func parse_achievement_run(run: String, block: Array[String]) -> Array:
	var by_first := {}  # first character -> known texts, longest first
	var known := block.duplicate()
	known.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for k: String in known:
		if k.length() > 3:
			by_first.get_or_add(k[0], []).append(k)
	var key_pattern := RegEx.create_from_string("^(feat|count):[a-z0-9]+")

	var tokens := []  # [kind, value]: text, key or icon
	var icon := ""
	var i := 0
	while i < run.length():
		var found := ""
		for k: String in by_first.get(run[i], []):
			if run.substr(i, k.length()) == k:
				found = k
				break
		var key: RegExMatch = key_pattern.search(run.substr(i, 40)) if run[i] in ["f", "c"] else null
		if found or key:
			if icon:
				tokens.append(["icon", icon])
				icon = ""
			if key and (not found or key.get_string().length() >= found.length()):
				tokens.append(["key", key.get_string()])
				i += key.get_string().length()
			else:
				tokens.append(["text", found])
				i += found.length()
		elif run[i] == GAP:
			if icon:
				tokens.append(["icon", icon])
				icon = ""
			i += 1
		else:
			icon += run[i]
			i += 1
	if icon:
		tokens.append(["icon", icon])

	var out := []
	var current: Variant = null
	for token: Array in tokens:
		var kind: String = token[0]
		var value: String = token[1]
		if kind == "text" and not value.ends_with("."):
			current = {"name": value}
			out.append(current)
		elif current == null:
			continue
		elif kind == "text":
			current["description"] = value
		else:
			current[kind] = value
	var previous_icon := ""
	var result := []
	for a: Dictionary in out:
		a.get_or_add("icon", previous_icon)  # the builder reuses the previous icon when none is given
		previous_icon = a["icon"]
		a.get_or_add("key", CODE_KEYS.get(a["name"], ""))
		var description: String = a.get("description", "")
		a["description"] = description.replace("{n}", str(SaveProgress.MAX_TALENT_POINTS))
		var key: String = a["key"]
		if key.begins_with("pieces:") and key != "pieces:all":
			a["description"] = PIECES_TEXT.replace("{n}", key.get_slice(":", 1))
		if key:
			a["group"] = achievement_group(key)
			result.append(a)
	return result


## The per-class and per-zone achievements the game generates from templates.
static func templated_achievements(classes: Array, zones: Array) -> Array:
	var out := []
	var last: Dictionary = zones[-1]
	var last_final := _final_boss(last)
	for c: Dictionary in classes:
		out.append({"key": "class:" + c["id"], "name": "%s Victorious" % c["name"],
				"description": "Win a run with a %s." % c["name"], "icon": c["icon"]})
		out.append({"key": "classlast:" + c["id"], "name": "%s of the Scarab Wall" % c["name"],
				"description": "Defeat %s at %s with a %s." % [last_final, last["name"], c["name"]], "icon": c["icon"]})
	for z: Dictionary in zones:
		var final := _final_boss(z)
		out.append({"key": "zone:" + z["id"], "name": z["name"],
				"description": "Defeat %s in %s with any class." % [final, z["name"]], "icon": ZONE_ICON})
		out.append({"key": "zone9:" + z["id"], "name": "Champion of %s" % z["name"],
				"description": "Defeat %s in %s with all nine classes." % [final, z["name"]], "icon": ZONE_ICON})
	for a: Dictionary in out:
		a["group"] = achievement_group(a["key"])
	return out


static func achievement_group(key: String) -> String:
	const GROUPS := {"count": "Counts", "feat": "Feats", "zone": "Zones", "zone9": "Zones",
			"class": "Classes", "classlast": "Classes"}
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
