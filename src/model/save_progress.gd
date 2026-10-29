class_name SaveProgress
extends RefCounted
## A save's progress as the game keeps it (its profile, 0.100.1 to 0.102.x), read from the save's text as the
## game's reader does and written back as its writer does.
##
## Reader (exe 0x87cf220): the text is split into lines at "\n" (a trailing "\r" dropped, each line trimmed) and each
## line at "|"; every kind has its own pass over all lines, with its own field count, number parsing (Rust's: an
## optional "+", digits only, no overflow) and clean-up: lists sorted and de-duplicated, the pick sanitized, a hero
## of a race its class may not be skipped. Lines of no known kind are dropped: the game has nowhere to keep them.
## Writer (exe 0x87d48f0): every record, in a fixed order, each line ending in "\n"; an empty profile writes nothing.
## So a save the game wrote reads and writes back to the same text, and any other save (an older build's, an edited
## one) comes out as the game would rewrite it on its next save.
## Talent sets are relearned by relearn_talents, which needs the game's talent trees; EditorSession calls it on
## opening and saving, as the game's reader relearns them. Hero and pick looks are not clamped to what a race offers
## (that needs the character models); the game clamps them when it reads the save.
## Classes are WoW class ids (1 warrior … 11 druid), as stored in the save.

const MAX_RARITY := 4  # 0 Common … 4 Legendary
const MIN_ZONES_OPEN := 1
## Heroic I–V. `hbeat` stores the highest tier beaten for each class and zone; beating a tier opens the next one.
const MAX_HEROIC_LEVEL := 5
## Gear upgrades and class mark balances in the current build.
const MAX_ITEM_STARS := 5
const MAX_CLASS_MARKS := 0xffffffff
## The zone-unlock repair's cap on zones open (0.102.3 on; an immediate in the reader, exe 0.103.1 0x8a980ec).
const REPAIR_MAX_ZONES_OPEN := 12
## The zones in the game's order (0.96.0 on): the reader's zone-id switch and the writer's zone table have them
## built in. The editor passes the zones read from the exe, which are the same.
const ZONE_ORDER: Array[String] = ["elwynn", "duskwood", "wsg", "ungoro", "ab", "feralas", "arena", "sm", "av", "brm",
		"aq", "naxx"]
## The zones a pre-0.96.0 `unlock|class|n` line counted, in their order then: the game reads n (clamped to 1-9) as
## "open up to the n-th of these" (exe 0x8f06de0), so zones added before them are open too.
const LEGACY_ZONES: Array[String] = ["elwynn", "duskwood", "wsg", "ab", "feralas", "arena", "av", "brm", "aq"]
## Talent XP curve, from the game's talents view (exe 0x1402c9de1): point n costs 65 + 15·n XP
## (80, 95, 110 … 830), for MAX_TALENT_POINTS points. Verified against a real save.
const MAX_TALENT_POINTS := 51
const _POINT_COST_BASE := 65
const _POINT_COST_STEP := 15
## From 0.98.0 each class keeps this many talent builds, Spec 1 to 3, one of them lit (played with).
const SPECS := 3
## The game's tree rules (exe 0x8550730): a row opens at this many points per row spent in lower rows of
## its tree, and of a tree's capstones (this row) only one can be learned.
const POINTS_PER_ROW := 5
const CAPSTONE_ROW := 6
## Talent XP that earns every point: the sum of all point costs (23 205).
@warning_ignore("integer_division")
const FULL_TALENT_XP := MAX_TALENT_POINTS * _POINT_COST_BASE \
		+ _POINT_COST_STEP * MAX_TALENT_POINTS * (MAX_TALENT_POINTS + 1) / 2
## The lifetime stats the stat line holds, in the order the game writes them (all seven, and only when one is not 0)
## and the only keys its reader knows (a key twice keeps the most).
const STATS: Array[String] = ["kills", "gold", "guardians", "bosses", "runs", "wins", "caches", "marks"]
## Lifetime stats that satisfy every count achievement.
const FULL_STATS := {
	"kills": 1000000, "gold": 50000, "guardians": 500, "bosses": 100, "runs": 100, "wins": 50, "caches": 100,
	"marks": 10000,
}
## Current-build records are kept verbatim until their editor changes them. This preserves the exact text of
## co-op clears, purchased races, marks, item stars, pity counters and weapon glows on unrelated edits.
const CURRENT_PASSTHROUGH_KINDS: Array[String] = ["coopbeat", "races", "marks", "stars", "pity", "glow"]
## The classes the game has (its class mask 0xbbe: 1-5, 7-9, 11).
const CLASSES: Array[int] = [1, 2, 3, 4, 5, 7, 8, 9, 11]
## The races each class may be, in the game's order (exe 0x9123490); the pick's sanitizer makes another race the
## first, the reader skips a hero of another race.
const ALLOWED_RACES := {1: [1, 2, 3, 4, 5, 6, 7, 8], 2: [1, 3], 3: [3, 4, 2, 6, 8], 4: [1, 3, 4, 7, 2, 5, 8],
		5: [1, 3, 4, 5, 8], 7: [2, 6, 8], 8: [1, 7, 5, 8], 9: [1, 7, 2, 5], 11: [4, 6]}
## A class's race on a new save, for heroes made by fill_all.
const DEFAULT_RACE := {1: 1, 2: 1, 3: 3, 4: 3, 5: 3, 7: 2, 8: 5, 9: 5, 11: 6}
const LOOKS := 5  ## skin, face, hair style, hair colour, facial hair
const SLOTS := 19  ## WoW inventory slots 0-18 in a class's gear record
## The pick's Run Options (density, health, damage, speed): min, max and step in %, as the game's table has them.
const RUN_OPTIONS := [[100, 500, 25], [100, 500, 25], [100, 300, 10], [100, 150, 5]]
const DEFAULT_HERO_NAME := "Hero"
const HERO_NAME_MOST := 12
const _U8 := 0xff
const _U16 := 0xffff
const _U32 := 0xffffffff
const _U64 := 0x7fffffffffffffff  # GDScript's int; the game's u64 counters never come near it
const _I64_DIGITS := "9223372036854775807"


## A hero record: a class's race, gender and look.
class HeroRecord:
	var race := 0
	var gender := 0
	var look: Array[int] = [0, 0, 0, 0, 0]

	func look_text() -> String:
		return ",".join(look.map(func(v: int) -> String: return str(v)))


## The WoW character list (no tag, ten fields a line). AZS saves have none; kept as read.
var _characters: Array[PackedStringArray] = []
## The pick line's fields after "pick|", sanitized; "" if there is none.
var _pick := ""
var _zones: Array[String] = []      # the zone order the save is read and written with
var _unlocked: Dictionary = {}      # class -> zones open (n), in the order the classes were first opened
var _items: Array[int] = []         # sorted, unique
## Per-class gear records, in the order they were made: class -> {"equip": {slot: id}, "look": {slot: value}}.
var _gear: Dictionary = {}
## Talent records in save order: [class, xp, ranks as [[id, rank]…]]. The game keeps every record it reads; the
## first of a class is the one it uses.
var _talents: Array = []
## 0.98.0's spec records: class -> {"lit": 0 … SPECS - 1, "builds": SPECS Arrays of [id, rank]}, in save order. A
## class has one only after its first switch (or an edit of another spec here); until then its Spec 1 is lit, holding
## the talent record's ranks, and Specs 2 and 3 are empty. The lit build mirrors the talent record's ranks.
var _specs: Dictionary = {}
var _seen: Array = []               # [id, rarity], sorted by id
var _achievements: Array[String] = []  # sorted
var _achieved_at: Dictionary = {}   # key -> unix time; written sorted by key
var _stats: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]  # in STATS order
var _beaten: Array = []             # [class, zone index], sorted
var _heroic_beaten: Array = []      # [class, zone index, highest tier beaten (1–5)], sorted
var _class_marks: Dictionary = {}   # class -> unspent marks (u32), in save order
var _item_stars: Dictionary = {}    # item id -> 1–5 stars; 0 is omitted
var _perks: Dictionary = {}         # perk id -> rank; written sorted by id
var _tabards: Array[int] = []       # bought tabards, sorted
var _companion_looks: Array[String] = []  # the pickup companions' chosen looks, slot 0 then 1
var _heroes: Dictionary = {}        # class -> HeroRecord, in save order
var _resets := 0                    # perk resets used
var _preserved_lines: Array[String] = []  # current-build records in CURRENT_PASSTHROUGH_KINDS, kept as read
var _marks_modified := false
var _stars_modified := false
var _modified := false


## A save's plain text read as the game reads it; `zones` are the game's zone ids in order.
static func from_text(text: String, zones: Array[String] = ZONE_ORDER) -> SaveProgress:
	var p := SaveProgress.new()
	p._zones = zones.duplicate()
	p._read(_records(text))
	return p


## The save's text as the game's writer writes it.
func to_text() -> String:
	var out := PackedStringArray()
	for r in _characters:
		out.append("|".join(r))
	if _pick != "":
		out.append("pick|" + _pick)
	for c: int in _unlocked:  # n == 0 is written as the first zone, past the last as the last
		out.append("open|%d|%s" % [c, _zones[maxi(mini(_unlocked[c], _zones.size()) - 1, 0)]])
	if not _items.is_empty():
		out.append("items|" + _join_ints(_items))
	for c: int in _gear:
		out.append("equip|%d|%s" % [c, _slots_text(_gear[c]["equip"])])
		out.append("look|%d|%s" % [c, _slots_text(_gear[c]["look"])])
	for t: Array in _talents:
		out.append("talent|%d|%d|%s" % [t[0], t[1], _ranks_text(t[2])])
	for c: int in _specs:  # spec|{class}|{lit}|{b0}|{b1}|{b2}, every build written, empty or not
		var builds := PackedStringArray()
		for build: Array in _specs[c]["builds"]:
			builds.append(_ranks_text(build))
		out.append("spec|%d|%d|%s" % [c, _specs[c]["lit"], "|".join(builds)])
	if not _seen.is_empty():
		out.append("seen|" + _join_pairs(_seen, "="))
	if not _achievements.is_empty():
		out.append("ach|" + ",".join(_achievements))
	if not _achieved_at.is_empty():
		var keys := _achieved_at.keys()
		keys.sort()
		out.append("achat|" + _join_pairs(keys.map(func(k: String) -> Array: return [k, _achieved_at[k]]), "="))
	if _stats.any(func(v: int) -> bool: return v != 0):
		var pairs := []
		for i in range(STATS.size()):
			pairs.append([STATS[i], _stats[i]])
		out.append("stat|" + _join_pairs(pairs, "="))
	var at := 0
	while at < _beaten.size():  # one line a class, its zones in zone order (the list is sorted)
		var c: int = _beaten[at][0]
		var zones := PackedStringArray()
		while at < _beaten.size() and _beaten[at][0] == c:
			zones.append(_zones[_beaten[at][1]])
			at += 1
		out.append("beat|%d|%s" % [c, ",".join(zones)])
	at = 0
	while at < _heroic_beaten.size():  # hbeat|class|zone:tier,…; one line per class
		var c: int = _heroic_beaten[at][0]
		var levels := PackedStringArray()
		while at < _heroic_beaten.size() and _heroic_beaten[at][0] == c:
			levels.append("%s:%d" % [_zones[_heroic_beaten[at][1]], _heroic_beaten[at][2]])
			at += 1
		out.append("hbeat|%d|%s" % [c, ",".join(levels)])
	if not _perks.is_empty():
		var ids := _perks.keys()
		ids.sort()
		out.append("perk|" + _join_pairs(ids.map(func(id: String) -> Array: return [id, _perks[id]]), ":"))
	if not _tabards.is_empty():
		out.append("tabard|" + _join_ints(_tabards))
	if not _companion_looks.is_empty():
		out.append("pets|" + ",".join(_companion_looks))
	if _resets != 0:
		out.append("resets|%d" % _resets)
	_append_current_records(out)
	for c: int in _heroes:
		var h: HeroRecord = _heroes[c]
		out.append("hero|%d|%d|%d|%s" % [c, h.race, h.gender, h.look_text()])
	return "" if out.is_empty() else "\n".join(out) + "\n"


## Whether anything changed since it was read.
func is_modified() -> bool:
	return _modified


# ---------------------------------------------------------------- the pick, heroes and zones

## The pick line's fields (class|race|gender|zone|name|look|options), sanitized as the game keeps them; "" if none.
func pick_text() -> String:
	return _pick


func hero_classes() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_heroes.keys())
	return ids


## A class's hero (a copy), or null if it has none.
func hero(class_id: int) -> HeroRecord:
	if not _heroes.has(class_id):
		return null
	var h: HeroRecord = _heroes[class_id]
	var copy := HeroRecord.new()
	copy.race = h.race
	copy.gender = h.gender
	copy.look = h.look.duplicate()
	return copy


## Gives a class a hero (its default race, male, the first look) if it has none; a new one goes after the others.
func ensure_hero(class_id: int) -> void:
	if _heroes.has(class_id):
		return
	var h := HeroRecord.new()
	h.race = DEFAULT_RACE.get(class_id, 1)
	_heroes[class_id] = h
	_modified = true


## The zone ids the save is read and written with, in the game's order.
func zone_ids() -> Array[String]:
	return _zones.duplicate()


## Zones open to a class: up to the furthest its `open|class|zone` lines (0.96.0 on) or `unlock|class|n` lines
## (before) name. A class without one has only its first zone open.
func zones_unlocked(class_id: int) -> int:
	return maxi(_unlocked.get(class_id, MIN_ZONES_OPEN), MIN_ZONES_OPEN)


## Sets the zones open to a class, clamped to MIN_ZONES_OPEN..the number of zones; saved as an `open|class|zone`
## line naming the last of them.
func set_zones_unlocked(class_id: int, count: int) -> void:
	var clamped := clampi(count, MIN_ZONES_OPEN, maxi(MIN_ZONES_OPEN, _zones.size()))
	if zones_unlocked(class_id) != clamped:
		_unlocked[class_id] = clamped
		_modified = true


func is_beaten(class_id: int, zone: String) -> bool:
	return _beaten.has([class_id, _zones.find(zone)])


## Marks a zone won (or not) by a class; the list stays sorted by (class, zone), as the game keeps it. A zone the
## game doesn't have can't be kept (the list holds zone indices).
func set_beaten(class_id: int, zone: String, beaten_now: bool) -> void:
	var entry := [class_id, _zones.find(zone)]
	if entry[1] < 0 or _beaten.has(entry) == beaten_now:
		return
	if beaten_now:
		_beaten.append(entry)
		_beaten.sort()
	else:
		_beaten.erase(entry)
	_modified = true


## Marks many zones won (or not) for a class at once.
func set_beaten_for(class_id: int, zones: Array[String], beaten_now: bool) -> void:
	for zone in zones:
		set_beaten(class_id, zone, beaten_now)


## Highest Heroic tier beaten by a class in a zone (0 means none). The current game stores 1–5.
func heroic_level(class_id: int, zone: String) -> int:
	var zone_index := _zones.find(zone)
	for entry: Array in _heroic_beaten:
		if entry[0] == class_id and entry[1] == zone_index:
			return entry[2]
	return 0


## Sets the highest Heroic tier beaten. Tier 5 makes Heroic I–V available; 0 removes the record.
func set_heroic_level(class_id: int, zone: String, level: int) -> void:
	var zone_index := _zones.find(zone)
	if zone_index < 0 or not CLASSES.has(class_id):
		return
	var kept := clampi(level, 0, MAX_HEROIC_LEVEL)
	for i in range(_heroic_beaten.size()):
		var entry: Array = _heroic_beaten[i]
		if entry[0] == class_id and entry[1] == zone_index:
			if entry[2] == kept:
				return
			if kept == 0:
				_heroic_beaten.remove_at(i)
			else:
				entry[2] = kept
			_modified = true
			return
	if kept > 0:
		_heroic_beaten.append([class_id, zone_index, kept])
		_heroic_beaten.sort()
		_modified = true


## Makes every Heroic tier available in every zone for one class.
func unlock_all_zone_difficulties(class_id: int) -> void:
	for zone in _zones:
		set_heroic_level(class_id, zone, MAX_HEROIC_LEVEL)


## Every zone won by a class, which also opens every zone.
func win_all_zones(class_id: int) -> void:
	set_beaten_for(class_id, _zones, true)
	set_zones_unlocked(class_id, _zones.size())


## No zone won by a class, back to only its first zone open.
func clear_zones(class_id: int) -> void:
	set_beaten_for(class_id, _zones, false)
	for zone in _zones:
		set_heroic_level(class_id, zone, 0)
	set_zones_unlocked(class_id, MIN_ZONES_OPEN)


# ---------------------------------------------------------------- talents

func talent_xp(class_id: int) -> int:
	var t := _talent_record(class_id)
	return t[1] if not t.is_empty() else 0


func set_talent_xp(class_id: int, xp: int) -> void:
	var kept := clampi(xp, 0, _U32)
	if talent_xp(class_id) == kept:
		return
	_talent_entry(class_id)[1] = kept
	_modified = true


## Spec arguments: a spec index 0 … SPECS - 1, or -1 (the default) for the lit spec, whose ranks are the
## talent record's. Editing another spec only changes its build.

func talent_rank(class_id: int, talent_id: String, spec: int = -1) -> int:
	return _rank_in(_ranks_of(class_id, spec), talent_id)


func set_talent_rank(class_id: int, talent_id: String, rank: int, spec: int = -1) -> void:
	if talent_rank(class_id, talent_id, spec) == rank:
		return
	var ranks := spec_ranks(class_id, spec)
	for i in range(ranks.size()):
		if ranks[i][0] == talent_id:
			if rank > 0:
				ranks[i][1] = rank
			else:
				ranks.remove_at(i)
			set_spec_ranks(class_id, spec, ranks)
			return
	ranks.append([talent_id, rank])
	set_spec_ranks(class_id, spec, ranks)


## Sets a talent's rank; learning it unlearns the talents it excludes (e.g. the other capstone).
func set_talent(class_id: int, talent: Dictionary, rank: int, spec: int = -1) -> void:
	set_talent_rank(class_id, talent["id"], rank, spec)
	if rank > 0:
		for other_id: String in talent.get("excludes", []):
			set_talent_rank(class_id, other_id, 0, spec)


## The spec a class plays with: its spec record's, else Spec 1 (exe 0x87cd3d0).
func lit_spec(class_id: int) -> int:
	return _specs[class_id]["lit"] if _specs.has(class_id) else 0


## Whether a class has a spec record, i.e. a `spec|` line.
func has_specs(class_id: int) -> bool:
	return _specs.has(class_id)


## A spec's ranks as saved, [id, rank] pairs (a copy): the lit one's are the talent record's, another's
## its build, empty without a spec record (exe 0x87cd3d0).
func spec_ranks(class_id: int, spec: int = -1) -> Array:
	return _ranks_of(class_id, spec).duplicate(true)


## Replaces a spec's ranks with `ranks` ([id, rank] pairs; rank 0 ones are dropped). The lit spec's go
## to the talent record and are mirrored to its build, as the game sets talents (exe 0x87d72b0).
## Another spec's go to its build, making the class's spec record if it has none.
func set_spec_ranks(class_id: int, spec: int, ranks: Array) -> void:
	if spec >= SPECS:
		return
	var kept := []
	for pair: Array in ranks:
		if pair[1] > 0:
			kept.append([pair[0], pair[1]])
	if _ranks_of(class_id, spec) == kept:
		return
	if _is_lit(class_id, spec):
		_talent_entry(class_id)[2] = kept
		_mirror_lit_spec(class_id)
	else:
		_spec_record(class_id)["builds"][spec] = kept
	_modified = true


## Lights another spec of a class, as the game's switch does (exe 0x87cd820): the lit spec's ranks are
## kept as its build, then the new spec's build, relearned within the class's points (as the game reads
## builds), becomes the talent record's ranks. `trees` are the class's three trees. Returns false, changing
## nothing, if `spec` is out of range or already lit.
func switch_spec(class_id: int, spec: int, trees: Array) -> bool:
	if spec < 0 or spec >= SPECS or spec == lit_spec(class_id):
		return false
	var record := _spec_record(class_id)
	record["builds"][record["lit"]] = spec_ranks(class_id)
	record["lit"] = spec
	_talent_entry(class_id)[2] = sanitized_ranks(trees, record["builds"][spec], talent_points_earned(class_id))
	_mirror_lit_spec(class_id)
	_modified = true
	return true


## Relearns every talent set as the game's reader does (exe 0x87cf220 → sanitizer 0x87e5650): a talent record's
## ranks within the points its XP earns, and each spec build within the points of its class's first talent record.
## `trees_of` gives a WoW class id's three trees (empty for a class the game doesn't have, whose sets come out empty).
## This is how 0.104.0 refunds the old Demonology points: its reader is 0.103.1's, so an old record is replayed against
## the new tree, which drops the talents that are gone and keeps those it shares only as far as their new rows allow.
func relearn_talents(trees_of: Callable) -> void:
	for t: Array in _talents:
		var kept := sanitized_ranks(trees_of.call(t[0]), t[2], talent_points_for_xp(t[1]))
		if kept != t[2]:
			t[2] = kept
			_modified = true
	for c: int in _specs:
		for i in range(SPECS):
			var build: Array = _specs[c]["builds"][i]
			var kept := sanitized_ranks(trees_of.call(c), build, talent_points_earned(c))
			if kept != build:
				_specs[c]["builds"][i] = kept
				_modified = true


## `ranks` ([id, rank] pairs) relearned from nothing within `points`, as the game's sanitizer does
## (exe 0x8550b50): talents of the class's `trees` only, at most their max rank, learned rank by rank in
## (row, tree, column) order while the tree rules allow. The result is in that order.
static func sanitized_ranks(trees: Array, ranks: Array, points: int) -> Array:
	var order := []
	for pair: Array in ranks:
		for ti in range(trees.size()):
			for t: Dictionary in trees[ti]["talents"]:
				if t["id"] == pair[0]:
					order.append([int(t.get("row", 0)), ti, int(t.get("col", 0)), t, mini(pair[1], int(t["ranks"]))])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a.slice(0, 3) < b.slice(0, 3))
	var out := []
	for entry: Array in order:
		for _rank in range(entry[4]):
			if _can_learn(trees, out, points, entry[1], entry[3]):
				_add_rank(out, entry[3]["id"])
	return out


## Whether one more rank of talent `t` (of tree `tree_index`) can be learned (0.104.0 0x8b02ce0, inlined in the
## sanitizer 0x8b03170; 0.94.1 0x8550730): a point left, below its max rank, its row open, no rival of its row learned
## (a capstone's other capstones, a choice's other choices: 0x8b025a0) and, if it has prerequisites, one of them
## (`requires`, else 0.104.0's `requires_or`) in the class at full rank (0x8b08de0).
static func _can_learn(trees: Array, ranks: Array, points: int, tree_index: int, t: Dictionary) -> bool:
	var spent := 0
	for pair: Array in ranks:
		spent += pair[1]
	var row := int(t.get("row", 0))
	if spent >= points or _rank_in(ranks, t["id"]) >= int(t["ranks"]):
		return false
	var below := 0
	var rivals: bool = row == CAPSTONE_ROW or t.get("exclusive", false)
	for other: Dictionary in trees[tree_index]["talents"]:
		var other_row := int(other.get("row", 0))
		if other_row < row:
			below += _rank_in(ranks, other["id"])
		elif rivals and other_row == row and other["id"] != t["id"] \
				and (row == CAPSTONE_ROW or other.get("exclusive", false)) and _rank_in(ranks, other["id"]) > 0:
			return false
	if below < POINTS_PER_ROW * row:
		return false
	var requires: String = t.get("requires", "")
	if requires == "":
		return true
	for id: String in [requires, t.get("requires_or", "")]:
		if id == "":
			continue
		for tree: Dictionary in trees:
			for other: Dictionary in tree["talents"]:
				if other["id"] == id and _rank_in(ranks, id) >= int(other["ranks"]):
					return true
	return false


static func _rank_in(ranks: Array, talent_id: String) -> int:
	for pair: Array in ranks:
		if pair[0] == talent_id:
			return pair[1]
	return 0


static func _add_rank(ranks: Array, talent_id: String) -> void:
	for pair: Array in ranks:
		if pair[0] == talent_id:
			pair[1] += 1
			return
	ranks.append([talent_id, 1])


func _is_lit(class_id: int, spec: int) -> bool:
	return spec < 0 or spec == lit_spec(class_id)


## The saved ranks of a spec (not a copy).
func _ranks_of(class_id: int, spec: int) -> Array:
	if _is_lit(class_id, spec):
		var t := _talent_record(class_id)
		return t[2] if not t.is_empty() else []
	if not _specs.has(class_id) or spec >= SPECS:
		return []
	return _specs[class_id]["builds"][spec]


## A class's spec record, made if missing (after the others): Spec 1 lit, with the talent record's ranks.
func _spec_record(class_id: int) -> Dictionary:
	if not _specs.has(class_id):
		_specs[class_id] = {"lit": 0, "builds": [spec_ranks(class_id), [], []]}
		_modified = true
	return _specs[class_id]


## The lit build mirrors the talent record's ranks whenever they change (exe 0x87d72b0).
func _mirror_lit_spec(class_id: int) -> void:
	if _specs.has(class_id):
		var record: Dictionary = _specs[class_id]
		record["builds"][record["lit"]] = spec_ranks(class_id)


## Talent points earned with this much talent XP (0 … MAX_TALENT_POINTS).
static func talent_points_for_xp(xp: int) -> int:
	var points := 0
	var left := xp
	while points < MAX_TALENT_POINTS:
		var cost := _POINT_COST_BASE + _POINT_COST_STEP * (points + 1)
		if left < cost:
			break
		left -= cost
		points += 1
	return points


## Talent XP needed to have earned this many points.
static func talent_xp_for_points(points: int) -> int:
	var n := clampi(points, 0, MAX_TALENT_POINTS)
	@warning_ignore("integer_division")
	return n * _POINT_COST_BASE + _POINT_COST_STEP * n * (n + 1) / 2


func talent_points_earned(class_id: int) -> int:
	return talent_points_for_xp(talent_xp(class_id))


func talent_points_spent(class_id: int, spec: int = -1) -> int:
	var spent := 0
	for pair: Array in _ranks_of(class_id, spec):
		spent += pair[1]
	return spent


## Points spent in one tree; `talents` are the tree's talent dictionaries (id, ranks, row, col).
func tree_points_spent(class_id: int, talents: Array, spec: int = -1) -> int:
	var spent := 0
	for t: Dictionary in talents:
		spent += talent_rank(class_id, t["id"], spec)
	return spent


## Fills a tree row by row (as the game unlocks rows) up to each talent's max rank, without the
## class going over MAX_TALENT_POINTS. Of talents that exclude each other, the one already learned,
## else the first, is kept. Raises talent XP to FULL_TALENT_XP so the points are earned.
func max_tree(class_id: int, talents: Array, spec: int = -1) -> void:
	var budget := MAX_TALENT_POINTS - (talent_points_spent(class_id, spec) - tree_points_spent(class_id, talents, spec))
	var ordered := talents.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [int(a.get("row", 0)), int(a.get("col", 0))] < [int(b.get("row", 0)), int(b.get("col", 0))])
	for t: Dictionary in ordered:
		var excluded := false
		for other_id: String in t.get("excludes", []):
			excluded = excluded or talent_rank(class_id, other_id, spec) > 0
		var rank := 0 if excluded else clampi(int(t["ranks"]), 0, maxi(budget, 0))
		set_talent_rank(class_id, t["id"], rank, spec)
		budget -= rank
	set_talent_xp(class_id, maxi(talent_xp(class_id), FULL_TALENT_XP))


func reset_tree(class_id: int, talents: Array, spec: int = -1) -> void:
	for t: Dictionary in talents:
		set_talent_rank(class_id, t["id"], 0, spec)


## Removes every spent rank of a class's spec; its talent XP is kept.
func reset_talents(class_id: int, spec: int = -1) -> void:
	set_spec_ranks(class_id, spec, [])


# ---------------------------------------------------------------- collection, codex, achievements, stats

func has_item(item_id: int) -> bool:
	return _items.has(item_id)


func set_item(item_id: int, owned: bool) -> void:
	if has_item(item_id) == owned:
		return
	if owned:
		_items.insert(_items.bsearch(item_id), item_id)
	else:
		_items.erase(item_id)
	_modified = true


func set_items(item_ids: PackedInt32Array, owned: bool) -> void:
	for item_id in item_ids:
		set_item(item_id, owned)


func item_count() -> int:
	return _items.size()


## Unspent equipment-upgrade marks for a class.
func class_marks(class_id: int) -> int:
	return _class_marks.get(class_id, 0)


func set_class_marks(class_id: int, amount: int) -> void:
	if not CLASSES.has(class_id):
		return
	var kept := clampi(amount, 0, MAX_CLASS_MARKS)
	if class_marks(class_id) == kept and (_class_marks.has(class_id) or kept == 0):
		return
	if kept > 0:
		_class_marks.erase(class_id)
		_class_marks[class_id] = kept
	else:
		_class_marks.erase(class_id)
	_marks_modified = true
	_modified = true


func set_all_class_marks(class_ids: Array[int], amount: int = MAX_CLASS_MARKS) -> void:
	for class_id in class_ids:
		set_class_marks(class_id, amount)


## Permanent upgrade stars on an equipment item (0–5).
func item_stars(item_id: int) -> int:
	return _item_stars.get(item_id, 0)


func set_item_stars(item_id: int, stars: int) -> void:
	var kept := clampi(stars, 0, MAX_ITEM_STARS)
	if item_stars(item_id) == kept:
		return
	if kept > 0:
		_item_stars[item_id] = kept
	else:
		_item_stars.erase(item_id)
	_stars_modified = true
	_modified = true


func set_item_stars_for(item_ids: PackedInt32Array, stars: int) -> void:
	for item_id in item_ids:
		set_item_stars(item_id, stars)


## What a class wears: WoW inventory slot (0-18) -> item id. Kept as read; the editor doesn't change it.
func worn(class_id: int) -> Dictionary:
	return _gear[class_id]["equip"].duplicate() if _gear.has(class_id) else {}


## How a class's gear looks, by WoW slot (0 hides it, a piece id shows that piece). Kept as read.
func looks(class_id: int) -> Dictionary:
	return _gear[class_id]["look"].duplicate() if _gear.has(class_id) else {}


## Highest rarity seen for a codex entry (jewel/amulet id or "legendary:<spell>"), -1 if never seen.
func seen_rarity(entry: String) -> int:
	for pair: Array in _seen:
		if pair[0] == entry:
			return pair[1]
	return -1


## Sets a codex entry's rarity (-1 removes it); the codex stays sorted by id, as the game keeps it.
func set_seen_rarity(entry: String, rarity: int) -> void:
	if seen_rarity(entry) == rarity:
		return
	for i in range(_seen.size()):
		if _seen[i][0] == entry:
			if rarity < 0:
				_seen.remove_at(i)
			else:
				_seen[i][1] = rarity
			_modified = true
			return
	_seen.append([entry, rarity])
	_seen.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_modified = true


## Sets the same rarity (-1 = not seen) for many codex entries at once.
func set_seen_rarity_for(entries: PackedStringArray, rarity: int) -> void:
	for entry in entries:
		set_seen_rarity(entry, rarity)


func has_achievement(key: String) -> bool:
	return _achievements.has(key)


## When `key` was earned (unix seconds), 0 if not or undated.
func achieved_at(key: String) -> int:
	return _achieved_at.get(key, 0)


## Earns (or takes back) an achievement. The key goes into the sorted list and, if it wasn't dated yet, gets `now`
## (unix seconds; 0 leaves it undated, as the game does when its clock doesn't answer). Taking it back drops its date.
func set_achievement(key: String, earned: bool, now: int) -> void:
	if has_achievement(key) == earned:
		return
	if earned:
		_achievements.insert(_achievements.bsearch(key), key)
		if now > 0 and not _achieved_at.has(key):
			_achieved_at[key] = now
	else:
		_achievements.erase(key)
		_achieved_at.erase(key)
	_modified = true


## Earns or clears many achievements at once; newly earned ones get `now` as their date.
func set_achievements(keys: PackedStringArray, earned: bool, now: int) -> void:
	for key in keys:
		set_achievement(key, earned, now)


func achievements() -> Array[String]:
	return _achievements.duplicate()


func stat(stat_name: String) -> int:
	var i := STATS.find(stat_name)
	return _stats[i] if i >= 0 else 0


## Sets a lifetime stat; the game keeps only the seven of STATS.
func set_stat(stat_name: String, value: int) -> void:
	var i := STATS.find(stat_name)
	if i < 0 or _stats[i] == maxi(value, 0):
		return
	_stats[i] = maxi(value, 0)
	_modified = true


# ---------------------------------------------------------------- perks, tabards, companions

## The account's perks: id -> rank.
func perks() -> Dictionary:
	return _perks.duplicate()


## Sets a perk's rank (0 removes it).
func set_perk_rank(perk_id: String, rank: int) -> void:
	var kept := clampi(rank, 0, _U8)
	if _perks.get(perk_id, 0) == kept:
		return
	if kept > 0:
		_perks[perk_id] = kept
	else:
		_perks.erase(perk_id)
	_modified = true


## Perk resets used (the game allows two).
func perk_resets() -> int:
	return _resets


func set_perk_resets(count: int) -> void:
	var kept := clampi(count, 0, _U32)
	if kept != _resets:
		_resets = kept
		_modified = true


## The tabards bought with perk points (the ones achievements earn aren't stored).
func tabards() -> Array[int]:
	return _tabards.duplicate()


func set_tabard(tabard_id: int, bought: bool) -> void:
	if _tabards.has(tabard_id) == bought:
		return
	if bought:
		_tabards.insert(_tabards.bsearch(tabard_id), tabard_id)
	else:
		_tabards.erase(tabard_id)
	_modified = true


## The looks chosen for the pickup companions, slot 0 then slot 1; empty for the default.
func companion_looks() -> Array[String]:
	return _companion_looks.duplicate()


## Sets the companions' looks; empty ids are left out, as the game reads the line.
func set_companion_looks(ids: Array[String]) -> void:
	var kept: Array[String] = []
	for id in ids:
		if id != "" and not id.contains(",") and not id.contains("|"):
			kept.append(id)
	if kept != _companion_looks:
		_companion_looks = kept
		_modified = true


# ---------------------------------------------------------------- 100%

## Everything unlocked: all heroes, zones open and won, full gear collection, legendary codex,
## every known achievement and matching stats, and enough talent XP for every point. Talent ranks
## already spent are kept; the rest is left to spend in game (respecs are free).
func fill_all(game: GameData, now: int) -> void:
	for c in game.classes:
		var class_id := int(c["wow_class_id"])
		ensure_hero(class_id)
		win_all_zones(class_id)
		unlock_all_zone_difficulties(class_id)
		set_items(game.item_ids_for_class(c["id"], class_id), true)
		set_class_marks(class_id, MAX_CLASS_MARKS)
		set_item_stars_for(game.item_ids_for_class(c["id"], class_id), MAX_ITEM_STARS)
		set_talent_xp(class_id, maxi(talent_xp(class_id), FULL_TALENT_XP))
		for spell: String in c["spell_pool"]:
			set_seen_rarity("legendary:" + spell, MAX_RARITY)
	for j in game.jewels + game.amulets:
		set_seen_rarity(j["id"], MAX_RARITY)
	for a in game.achievements:
		set_achievement(a["key"], true, now)
	for stat_name: String in FULL_STATS:
		set_stat(stat_name, maxi(stat(stat_name), FULL_STATS[stat_name]))


# ---------------------------------------------------------------- reading

## The text's lines as the reader splits them: at "\n" (no line after a final one), a trailing "\r" dropped,
## trimmed, then split at "|".
static func _records(text: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var lines := text.split("\n")
	if text.ends_with("\n") or text.is_empty():
		lines.remove_at(lines.size() - 1)
	for line in lines:
		out.append(line.trim_suffix("\r").strip_edges().split("|"))
	return out


func _read(records: Array[PackedStringArray]) -> void:
	for r in records:
		_read_character(r)
		_read_pick(r)
		_read_open(r)
		_read_gear(r)
		_read_talent(r)
		_read_spec(r)
		_read_hero(r)
	_read_lists(records)


## A WoW character line: ten fields, the guid u64, the name, class, race and gender u8, a look of five u8 and four
## u32. Never in an AZS save.
func _read_character(r: PackedStringArray) -> void:
	if r.size() != 10 or _uint(r[0], _U64) < 0 or _u8_list(r[5]).size() != LOOKS:
		return
	var kept := PackedStringArray([str(_uint(r[0], _U64)), r[1]])
	for i in [2, 3, 4]:
		kept.append(str(_uint(r[i], _U8)))
	kept.append(_join_ints(_u8_list(r[5])))
	for i in [6, 7, 8, 9]:
		kept.append(str(_uint(r[i], _U32)))
	if not kept.has("-1"):
		_characters.append(kept)


## pick|class|race|gender|zone|name[|look[|options]] (6-8 fields): the last readable one is kept, sanitized as the
## game's pick sanitizer does (exe 0x87d7620): an unknown class becomes the Warrior, a race the class may not be its
## first one, gender a bool, an unknown zone the first, a name that isn't valid "Hero" (a valid one capitalised), the
## look 5 values (0s otherwise) and the Run Options 4 values within their table (100 each otherwise).
func _read_pick(r: PackedStringArray) -> void:
	if r.size() < 6 or r.size() > 8 or r[0] != "pick":
		return
	var class_id := _uint(r[1], _U8)
	var race := _uint(r[2], _U8)
	var gender := _uint(r[3], _U8)
	if class_id < 0 or race < 0 or gender < 0:
		return
	if not CLASSES.has(class_id):
		class_id = 1
	var allowed: Array = ALLOWED_RACES[class_id]
	var zone := r[4]
	if not _zones.has(zone) and not _zones.is_empty():
		zone = _zones[0]
	var look: Array[int] = [0, 0, 0, 0, 0]
	if r.size() > 6 and _u8_list(r[6]).size() == LOOKS:
		look = _u8_list(r[6])
	var options: Array[int] = []
	if r.size() > 7:
		options = _uint_list(r[7], _U16)
	var shown: Array[int] = []
	for i in range(RUN_OPTIONS.size()):
		shown.append(_clamp_option(i, options[i] if options.size() == RUN_OPTIONS.size() else 100))
	var hero_name := _typed_name(r[5].strip_edges()) if _valid_name(r[5]) else DEFAULT_HERO_NAME
	_pick = "%d|%d|%d|%s|%s|%s|%s" % [class_id, race if allowed.has(race) else int(allowed[0]), 1 if gender != 0 else 0,
			zone, hero_name, _join_ints(look), _join_ints(shown)]


## open|class|zone and 0.95's unlock|class|n (3 fields each): a class's furthest open zone. An unknown zone is
## skipped; unlock's n (1..9, 0 read as 1) names a zone in 0.95's order. A class's later record keeps the larger.
func _read_open(r: PackedStringArray) -> void:
	if r.size() != 3 or (r[0] != "open" and r[0] != "unlock"):
		return
	var class_id := _uint(r[1], _U8)
	if class_id < 0:
		return
	var zone := r[2]
	if r[0] == "unlock":
		var n := _uint(r[2], _U64)
		if n < 0:
			return
		zone = LEGACY_ZONES[clampi(n, 1, LEGACY_ZONES.size()) - 1]
	var count := _zones.find(zone) + 1
	if count > 0:
		_unlocked[class_id] = maxi(_unlocked.get(class_id, 0), count)


## The zone-unlock repair (0.102.3; profile reader 0x8a98088-0x8a98179 in 0.103.1): after the lists are read, each
## beaten (class, zone index z) opens the zone after it, so the class has at least min(z + 2, 12) zones open; a class
## without an open record gets one, after the others. It undoes an older build's save that locked every class back to
## the first zone, and opens Naxxramas to a class that beat the Gates of Ahn'Qiraj before Naxxramas came. The count
## also stays within the zones the save is read with (the writer names the last of them either way).
func _open_after_beaten() -> void:
	for entry: Array in _beaten:
		var count := mini(mini(entry[1] + 2, REPAIR_MAX_ZONES_OPEN), _zones.size())
		_unlocked[entry[0]] = maxi(_unlocked.get(entry[0], 0), count)


## equip|class|slot:id,… and look|class|slot:value,… (3 fields): a class's gear record, made by its first line of
## either kind; a later line sets its slots over the earlier ones. A slot past 18 is skipped.
func _read_gear(r: PackedStringArray) -> void:
	if r.size() != 3 or (r[0] != "equip" and r[0] != "look"):
		return
	var class_id := _uint(r[1], _U8)
	if class_id < 0:
		return
	if not _gear.has(class_id):
		_gear[class_id] = {"equip": {}, "look": {}}
	for pair: Array in _pairs(r[2], ":", _U8, _U32):
		if pair[0] < SLOTS:
			_gear[class_id][r[0]][pair[0]] = pair[1]


## talent|class|xp|id:rank,… (exactly 4 fields): every record is kept, in order.
func _read_talent(r: PackedStringArray) -> void:
	if r.size() != 4 or r[0] != "talent":
		return
	var class_id := _uint(r[1], _U8)
	var xp := _uint(r[2], _U32)
	if class_id >= 0 and xp >= 0:
		_talents.append([class_id, xp, _pairs(r[3], ":", -1, _U8)])


## spec|class|lit|b0|b1|b2 (at least 3 fields; lit 0-2; exe 0x87d0c74): a later record of a class replaces an
## earlier one and goes after the others.
func _read_spec(r: PackedStringArray) -> void:
	if r.size() < 3 or r[0] != "spec":
		return
	var class_id := _uint(r[1], _U8)
	var lit := _uint(r[2], _U8)
	if class_id < 0 or lit < 0 or lit >= SPECS:
		return
	var builds := []
	for i in range(SPECS):
		builds.append(_pairs(r[3 + i], ":", -1, _U8) if r.size() > 3 + i else [])
	_specs.erase(class_id)
	_specs[class_id] = {"lit": lit, "builds": builds}


## hero|class|race|gender|look (exactly 5 fields): skipped unless the class is the game's and the race one it may be;
## gender a bool, the look 5 values (0s otherwise). A later record of a class replaces an earlier one and goes after
## the others.
func _read_hero(r: PackedStringArray) -> void:
	if r.size() != 5 or r[0] != "hero":
		return
	var class_id := _uint(r[1], _U8)
	var race := _uint(r[2], _U8)
	var gender := _uint(r[3], _U8)
	if not CLASSES.has(class_id) or not ALLOWED_RACES[class_id].has(race) or gender < 0:
		return
	var h := HeroRecord.new()
	h.race = race
	h.gender = 1 if gender != 0 else 0
	var look := _u8_list(r[4])
	if look.size() == LOOKS:
		h.look = look
	_heroes.erase(class_id)
	_heroes[class_id] = h


## The list lines, each over every line of its kind: items, seen, ach, achat, stat, beat, perk, tabard (sorted and
## de-duplicated), resets (the first), pets (the last).
func _read_lists(records: Array[PackedStringArray]) -> void:
	var seen := {}
	var dated := []
	var perk_pairs := []
	var resets_read := false
	for r in records:
		if r.size() < 2:
			continue
		if CURRENT_PASSTHROUGH_KINDS.has(r[0]):
			_preserved_lines.append("|".join(r))
			if r[0] == "marks" and r.size() == 3:
				var class_id := _uint(r[1], _U8)
				var amount := _uint(r[2], _U32)
				if CLASSES.has(class_id) and amount >= 0:
					_class_marks.erase(class_id)
					_class_marks[class_id] = amount
			elif r[0] == "stars" and r.size() == 2:
				for pair: Array in _pairs(r[1], ":", _U32, _U8):
					if pair[1] > 0:
						_item_stars[pair[0]] = mini(pair[1], MAX_ITEM_STARS)
			continue
		var rest := "|".join(r.slice(1))
		match r[0]:
			"items":
				_items.append_array(_uint_list(rest, _U32, true))
			"tabard":
				_tabards.append_array(_uint_list(rest, _U32, true))
			"seen":  # an entry twice keeps its highest rarity
				for pair: Array in _pairs(rest, "=", -1, _U8):
					seen[pair[0]] = maxi(seen.get(pair[0], 0), pair[1])
			"ach":
				for key in rest.split(",", false):
					if not _achievements.has(key):
						_achievements.append(key)
			"achat":
				dated.append_array(_pairs(rest, "=", -1, _U64))
			"stat":  # a key twice keeps the most; unknown keys are dropped
				for pair: Array in _pairs(rest, "=", -1, _U64):
					var i := STATS.find(pair[0])
					if i >= 0:
						_stats[i] = maxi(_stats[i], pair[1])
			"beat":  # zones joined by ","; unknown ones skipped
				var class_id := _uint(r[1], _U8)
				if r.size() >= 3 and class_id >= 0:
					for zone in r[2].split(","):
						var entry := [class_id, _zones.find(zone)]
						if entry[1] >= 0 and not _beaten.has(entry):
							_beaten.append(entry)
			"hbeat":  # hbeat|class|zone:tier,…; duplicates keep the highest tier, clamped to V
				var class_id := _uint(r[1], _U8)
				if r.size() == 3 and CLASSES.has(class_id):
					for pair: Array in _pairs(r[2], ":", -1, _U8):
						var zone_index := _zones.find(pair[0])
						if zone_index < 0 or pair[1] == 0:
							continue
						var found := false
						for entry: Array in _heroic_beaten:
							if entry[0] == class_id and entry[1] == zone_index:
								entry[2] = maxi(entry[2], mini(pair[1], MAX_HEROIC_LEVEL))
								found = true
								break
						if not found:
							_heroic_beaten.append([class_id, zone_index, mini(pair[1], MAX_HEROIC_LEVEL)])
			"perk":
				perk_pairs.append_array(_pairs(rest, ":", -1, _U8))
			"resets":
				if not resets_read and r.size() == 2 and _uint(r[1], _U32) >= 0:
					_resets = _uint(r[1], _U32)
					resets_read = true
			"pets":
				_companion_looks.assign(rest.split(",", false))
	_items = _sorted_unique(_items)
	_tabards = _sorted_unique(_tabards)
	var ids := seen.keys()
	ids.sort()
	for id: String in ids:
		_seen.append([id, seen[id]])
	_achievements.sort()
	_beaten.sort()
	_heroic_beaten.sort()
	_open_after_beaten()
	dated.sort()
	for pair: Array in dated:  # a key twice keeps its earliest time
		if not _achieved_at.has(pair[0]):
			_achieved_at[pair[0]] = pair[1]
	perk_pairs.sort()
	for pair: Array in perk_pairs:  # a perk twice keeps its lowest rank
		if not _perks.has(pair[0]):
			_perks[pair[0]] = pair[1]


## Keeps untouched modern records byte-for-byte. Once marks or stars are edited, replaces all records of that kind
## at their first old position (or appends them if the save had none).
func _append_current_records(out: PackedStringArray) -> void:
	var wrote_marks := false
	var wrote_stars := false
	for line in _preserved_lines:
		var kind := line.get_slice("|", 0)
		if kind == "marks" and _marks_modified:
			if not wrote_marks:
				_append_marks(out)
				wrote_marks = true
			continue
		if kind == "stars" and _stars_modified:
			if not wrote_stars:
				_append_stars(out)
				wrote_stars = true
			continue
		out.append(line)
	if _marks_modified and not wrote_marks:
		_append_marks(out)
	if _stars_modified and not wrote_stars:
		_append_stars(out)


func _append_marks(out: PackedStringArray) -> void:
	for class_id: int in CLASSES:
		if _class_marks.get(class_id, 0) > 0:
			out.append("marks|%d|%d" % [class_id, _class_marks[class_id]])


func _append_stars(out: PackedStringArray) -> void:
	var ids := _item_stars.keys()
	ids.sort()
	var pairs := []
	for id: int in ids:
		if _item_stars[id] > 0:
			pairs.append([id, _item_stars[id]])
	if not pairs.is_empty():
		out.append("stars|" + _join_pairs(pairs, ":"))


# ---------------------------------------------------------------- helpers

## A Run Option in % as the game keeps it: below its min the min, else down to its step and at most its max.
static func _clamp_option(index: int, percent: int) -> int:
	var o: Array = RUN_OPTIONS[index]
	if percent < o[0]:
		return o[0]
	@warning_ignore("integer_division")
	return o[0] + (mini(percent, o[1]) - o[0]) / o[2] * o[2]


## A typed hero name as the game keeps it: ASCII letters only, at most 12, capitalised.
static func _typed_name(text: String) -> String:
	var kept := ""
	for ch in text:
		var code := ch.unicode_at(0)
		if kept.length() < HERO_NAME_MOST and ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)):
			kept += ch
	return kept.left(1).to_upper() + kept.substr(1).to_lower()


## Whether the game keeps `text` (trimmed) as a hero name: 2-12 ASCII letters.
static func _valid_name(text: String) -> bool:
	var t := text.strip_edges()
	return t.length() >= 2 and t.length() <= HERO_NAME_MOST \
			and _typed_name(t) == t.left(1).to_upper() + t.substr(1).to_lower()


## `text` as an unsigned number no larger than `most`, as Rust parses one (an optional "+", then digits only); -1 if
## it isn't one.
static func _uint(text: String, most: int) -> int:
	var digits := text.trim_prefix("+")
	if digits.is_empty():
		return -1
	for ch in digits:
		if ch < "0" or ch > "9":
			return -1
	var significant := digits.lstrip("0")
	if significant.length() > _I64_DIGITS.length() \
			or significant.length() == _I64_DIGITS.length() and significant > _I64_DIGITS:
		return -1
	var value := significant.to_int()
	return value if value <= most else -1


## A list of u8 values joined by ","; empty if any isn't one.
static func _u8_list(text: String) -> Array[int]:
	return _uint_list(text, _U8)


## A list of numbers joined by ","; empty if any isn't one. `skip_empty`: empty items are skipped.
static func _uint_list(text: String, most: int, skip_empty := false) -> Array[int]:
	var out: Array[int] = []
	if text.is_empty():
		return out
	for part in text.split(",", not skip_empty):
		var v := _uint(part, most)
		if v < 0:
			return [] as Array[int]
		out.append(v)
	return out


## `key<separator>value` pairs joined by ","; a pair that doesn't read is skipped. `key_most` -1: the key is a
## string, else a number up to it.
static func _pairs(text: String, separator: String, key_most: int, value_most: int) -> Array:
	var out := []
	for part in text.split(",", false):
		var at := part.find(separator)
		if at < 0:
			continue
		var value := _uint(part.substr(at + 1), value_most)
		if value < 0:
			continue
		if key_most < 0:
			out.append([part.substr(0, at), value])
		elif _uint(part.substr(0, at), key_most) >= 0:
			out.append([_uint(part.substr(0, at), key_most), value])
	return out


static func _ranks_text(pairs: Array) -> String:
	var parts := PackedStringArray()
	for pair: Array in pairs:
		parts.append("%s:%d" % pair)
	return ",".join(parts)


## A gear record's slots in slot order: slot:value for every slot set.
static func _slots_text(slots: Dictionary) -> String:
	var keys := slots.keys()
	keys.sort()
	return ",".join(keys.map(func(slot: int) -> String: return "%d:%d" % [slot, slots[slot]]))


static func _sorted_unique(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for v in values:
		if not out.has(v):
			out.append(v)
	out.sort()
	return out


static func _join_ints(values: Array[int]) -> String:
	return ",".join(values.map(func(v: int) -> String: return str(v)))


static func _join_pairs(pairs: Array, separator: String) -> String:
	var parts := PackedStringArray()
	for pair: Array in pairs:
		parts.append("%s%s%d" % [pair[0], separator, pair[1]])
	return ",".join(parts)


## A class's first talent record, or [] if it has none.
func _talent_record(class_id: int) -> Array:
	for t: Array in _talents:
		if t[0] == class_id:
			return t
	return []


func _talent_entry(class_id: int) -> Array:
	var t := _talent_record(class_id)
	if t.is_empty():
		t = [class_id, 0, []]
		_talents.append(t)
	return t
