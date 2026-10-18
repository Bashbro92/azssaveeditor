class_name SaveProgress
extends RefCounted
## Typed, editable view of a save's progression records over a SaveDoc.
##
## Understands: hero, open (and the older unlock), beat, talent, spec, items, seen, ach, achat, stat. Every other record (pick,
## equip, look, perk, tabard, pets, resets, unknown kinds) is left untouched. Only record kinds that
## were changed are rewritten, so an unedited save writes back byte for byte.
## Classes are WoW class ids (1 warrior … 11 druid), as stored in the save.

const MAX_RARITY := 4  # 0 Common … 4 Legendary
const MIN_ZONES_OPEN := 1
## The zones a pre-0.96.0 `unlock|class|n` line counted, in their order then: the game reads n (clamped
## to 1-9) as "open up to the n-th of these" (ELF 0x8f06de0), so zones added before them are open too.
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
## Lifetime stats that satisfy every count achievement.
const FULL_STATS := {
	"kills": 1000000, "gold": 50000, "guardians": 500, "bosses": 100, "runs": 100, "wins": 50, "caches": 100,
}
## A vanilla-legal default race per class id for heroes created by fill_all.
const _DEFAULT_RACE := {1: 1, 2: 1, 3: 2, 4: 1, 5: 1, 7: 2, 8: 1, 9: 1, 11: 6}

var doc: SaveDoc
var heroes: Dictionary = {}        # class -> PackedStringArray record
var opened: Dictionary = {}        # class -> zone ids open up to (the game takes the furthest)
var _beaten: Array = []            # [class, zone id] in save order
var _talents: Dictionary = {}      # class -> {"xp": int, "ranks": Array of [id, rank]}
var _talent_order: Array[int] = []
## 0.98.0's spec records: class -> {"lit": 0 … SPECS - 1, "builds": SPECS Arrays of [id, rank]}, in save
## order. A class has one only after its first switch (or an edit of another spec here); until then its
## Spec 1 is lit, holding the talent record's ranks, and Specs 2 and 3 are empty. The talent record
## always holds the lit spec's ranks, and the lit build mirrors them.
var _specs: Dictionary = {}
var _items: Array[int] = []
var _seen: Array = []              # [id, rarity]
var _achievements: Array[String] = []
var _achieved_at: Dictionary = {}  # key -> unix time
var _stats: Array = []             # [name, value]
var _dirty: Dictionary = {}


static func from_doc(save_doc: SaveDoc) -> SaveProgress:
	var p := SaveProgress.new()
	p.doc = save_doc
	p._read()
	return p


static func from_text(text: String) -> SaveProgress:
	return from_doc(SaveDoc.parse(text))


func to_text() -> String:
	_write_dirty()
	return doc.to_text()


func is_modified() -> bool:
	return not _dirty.is_empty()


# ---------------------------------------------------------------- heroes and zones

func hero_classes() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(heroes.keys())
	return ids


func ensure_hero(class_id: int) -> void:
	if heroes.has(class_id):
		return
	heroes[class_id] = PackedStringArray(["hero", str(class_id), str(_DEFAULT_RACE.get(class_id, 1)), "0", "0,0,0,0,0"])
	_dirty["hero"] = true


## How many of `zones` (the game's zone ids, in order) are open to a class: up to the furthest its
## `open|class|zone` lines (0.96.0 on) or `unlock|class|n` lines (before) name. A class without one has
## only its first zone open.
func zones_unlocked(class_id: int, zones: PackedStringArray) -> int:
	var count := MIN_ZONES_OPEN
	for zone: String in opened.get(class_id, []):
		count = maxi(count, zones.find(zone) + 1)
	return count


## Sets the zones open to a class, clamped to MIN_ZONES_OPEN..the number of `zones`; saved as an
## `open|class|zone` line naming the last of them (and the older unlock lines dropped).
func set_zones_unlocked(class_id: int, count: int, zones: PackedStringArray) -> void:
	var clamped := clampi(count, MIN_ZONES_OPEN, maxi(MIN_ZONES_OPEN, zones.size()))
	if zones.is_empty() or zones_unlocked(class_id, zones) == clamped:
		return
	opened[class_id] = [zones[clamped - 1]]
	_dirty["open"] = true


func is_beaten(class_id: int, zone: String) -> bool:
	return _beaten.has([class_id, zone])


func set_beaten(class_id: int, zone: String, beaten_now: bool) -> void:
	if is_beaten(class_id, zone) == beaten_now:
		return
	if beaten_now:
		_beaten.append([class_id, zone])
	else:
		_beaten.erase([class_id, zone])
	_dirty["beat"] = true


## Marks many zones won (or not) for a class at once.
func set_beaten_for(class_id: int, zones: PackedStringArray, beaten_now: bool) -> void:
	for zone in zones:
		set_beaten(class_id, zone, beaten_now)


## Every zone won by a class, which also opens every zone.
func win_all_zones(class_id: int, zones: PackedStringArray) -> void:
	set_beaten_for(class_id, zones, true)
	set_zones_unlocked(class_id, zones.size(), zones)


## No zone won by a class, back to only its first zone open.
func clear_zones(class_id: int, zones: PackedStringArray) -> void:
	set_beaten_for(class_id, zones, false)
	set_zones_unlocked(class_id, MIN_ZONES_OPEN, zones)


# ---------------------------------------------------------------- talents

func talent_xp(class_id: int) -> int:
	return _talents.get(class_id, {}).get("xp", 0)


func set_talent_xp(class_id: int, xp: int) -> void:
	if talent_xp(class_id) == xp:
		return
	_talent_entry(class_id)["xp"] = maxi(0, xp)
	_dirty["talent"] = true


## Spec arguments: a spec index 0 … SPECS - 1, or -1 (the default) for the lit spec, whose ranks are the
## talent record's. Editing another spec only changes its build.

func talent_rank(class_id: int, talent_id: String, spec: int = -1) -> int:
	for pair in _ranks_of(class_id, spec):
		if pair[0] == talent_id:
			return pair[1]
	return 0


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


# ---------------------------------------------------------------- talent specs

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
		_talent_entry(class_id)["ranks"] = kept
		_dirty["talent"] = true
		_mirror_lit_spec(class_id)
	else:
		_spec_record(class_id)["builds"][spec] = kept
		_dirty["spec"] = true


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
	_dirty["spec"] = true
	var ranks := sanitized_ranks(trees, record["builds"][spec], talent_points_earned(class_id))
	if ranks != _talents.get(class_id, {}).get("ranks", []):
		_talent_entry(class_id)["ranks"] = ranks
		_dirty["talent"] = true
	_mirror_lit_spec(class_id)
	return true


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


## Whether one more rank of talent `t` (of tree `tree_index`) can be learned (exe 0x8550730).
static func _can_learn(trees: Array, ranks: Array, points: int, tree_index: int, t: Dictionary) -> bool:
	var spent := 0
	for pair: Array in ranks:
		spent += pair[1]
	var row := int(t.get("row", 0))
	if spent >= points or _rank_in(ranks, t["id"]) >= int(t["ranks"]):
		return false
	var below := 0
	for other: Dictionary in trees[tree_index]["talents"]:
		var other_row := int(other.get("row", 0))
		if other_row < row:
			below += _rank_in(ranks, other["id"])
		elif row == CAPSTONE_ROW and other_row == CAPSTONE_ROW and other["id"] != t["id"] \
				and _rank_in(ranks, other["id"]) > 0:
			return false
	if below < POINTS_PER_ROW * row:
		return false
	var requires: String = t.get("requires", "")
	if requires != "":
		var needed := {}
		for tree: Dictionary in trees:
			for other: Dictionary in tree["talents"]:
				if other["id"] == requires:
					needed = other
		if needed.is_empty() or _rank_in(ranks, requires) < int(needed["ranks"]):
			return false
	return true


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
		return _talents.get(class_id, {}).get("ranks", [])
	if not _specs.has(class_id) or spec >= SPECS:
		return []
	return _specs[class_id]["builds"][spec]


## A class's spec record, made if missing: Spec 1 lit, with the talent record's ranks.
func _spec_record(class_id: int) -> Dictionary:
	if not _specs.has(class_id):
		_specs[class_id] = {"lit": 0, "builds": [spec_ranks(class_id), [], []]}
		_dirty["spec"] = true
	return _specs[class_id]


## The lit build mirrors the talent record's ranks whenever they change (exe 0x87d72b0).
func _mirror_lit_spec(class_id: int) -> void:
	if not _specs.has(class_id):
		return
	var record: Dictionary = _specs[class_id]
	var ranks := spec_ranks(class_id)
	if record["builds"][record["lit"]] != ranks:
		record["builds"][record["lit"]] = ranks
		_dirty["spec"] = true


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
	for pair in _ranks_of(class_id, spec):
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
		return [int(a["row"]), int(a["col"])] < [int(b["row"]), int(b["col"])])
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
	_dirty["items"] = true


func set_items(item_ids: PackedInt32Array, owned: bool) -> void:
	for item_id in item_ids:
		set_item(item_id, owned)


func item_count() -> int:
	return _items.size()


## Highest rarity seen for a codex entry (jewel/amulet id or "legendary:<spell>"), -1 if never seen.
func seen_rarity(entry: String) -> int:
	for pair in _seen:
		if pair[0] == entry:
			return pair[1]
	return -1


func set_seen_rarity(entry: String, rarity: int) -> void:
	if seen_rarity(entry) == rarity:
		return
	for i in range(_seen.size()):
		if _seen[i][0] == entry:
			if rarity < 0:
				_seen.remove_at(i)
			else:
				_seen[i][1] = rarity
			_dirty["seen"] = true
			return
	_seen.append([entry, rarity])
	_dirty["seen"] = true


## Sets the same rarity (-1 = not seen) for many codex entries at once.
func set_seen_rarity_for(entries: PackedStringArray, rarity: int) -> void:
	for entry in entries:
		set_seen_rarity(entry, rarity)


func has_achievement(key: String) -> bool:
	return _achievements.has(key)


func set_achievement(key: String, earned: bool, now: int) -> void:
	if has_achievement(key) == earned:
		return
	if earned:
		_achievements.append(key)
		_achieved_at[key] = now
	else:
		_achievements.erase(key)
		_achieved_at.erase(key)
	_dirty["ach"] = true


## Earns or clears many achievements at once; newly earned ones get `now` as their date.
func set_achievements(keys: PackedStringArray, earned: bool, now: int) -> void:
	for key in keys:
		set_achievement(key, earned, now)


func achievements() -> Array[String]:
	return _achievements.duplicate()


func stat(stat_name: String) -> int:
	for pair in _stats:
		if pair[0] == stat_name:
			return pair[1]
	return 0


func set_stat(stat_name: String, value: int) -> void:
	if stat(stat_name) == value:
		return
	for pair in _stats:
		if pair[0] == stat_name:
			pair[1] = value
			_dirty["stat"] = true
			return
	_stats.append([stat_name, value])
	_dirty["stat"] = true


# ---------------------------------------------------------------- 100%

## Everything unlocked: all heroes, zones open and won, full gear collection, legendary codex,
## every known achievement and matching stats, and enough talent XP for every point. Talent ranks
## already spent are kept; the rest is left to spend in game (respecs are free).
func fill_all(game: GameData, now: int) -> void:
	var zones := game.zone_ids()
	for c in game.classes:
		var class_id := int(c["wow_class_id"])
		ensure_hero(class_id)
		win_all_zones(class_id, zones)
		set_items(game.item_ids_for_class(c["id"], class_id), true)
		set_talent_xp(class_id, maxi(talent_xp(class_id), FULL_TALENT_XP))
		for spell: String in c["spell_pool"]:
			set_seen_rarity("legendary:" + spell, MAX_RARITY)
	for j in game.jewels + game.amulets:
		set_seen_rarity(j["id"], MAX_RARITY)
	for a in game.achievements:
		set_achievement(a["key"], true, now)
	for stat_name: String in FULL_STATS:
		set_stat(stat_name, maxi(stat(stat_name), FULL_STATS[stat_name]))


# ---------------------------------------------------------------- reading and writing records

func _read() -> void:
	for r in doc.records_of("hero"):
		heroes[r[1].to_int()] = r
	for r in doc.records_of("unlock"):
		var n := clampi(_field(r, 2).to_int(), 1, LEGACY_ZONES.size())
		opened.get_or_add(r[1].to_int(), []).append(LEGACY_ZONES[n - 1])
	for r in doc.records_of("open"):
		opened.get_or_add(r[1].to_int(), []).append(_field(r, 2))
	for r in doc.records_of("beat"):
		_beaten.append([r[1].to_int(), r[2]])
	for r in doc.records_of("talent"):
		_talents[r[1].to_int()] = {"xp": r[2].to_int(), "ranks": _parse_ranks(_field(r, 3))}
		_talent_order.append(r[1].to_int())
	for r in doc.records_of("spec"):  # the game's spec pass (exe 0x87d0c74): a later line of a class replaces it
		if r.size() < 3 or not _is_u8(r[1]) or not _is_u8(r[2]) or r[2].to_int() >= SPECS:
			continue
		var builds := []
		for i in range(SPECS):
			builds.append(_parse_ranks(_field(r, 3 + i)))
		_specs.erase(r[1].to_int())
		_specs[r[1].to_int()] = {"lit": r[2].to_int(), "builds": builds}
	for id in _split_list(_field(doc.first("items"), 1)):
		_items.append(id.to_int())
	for pair in _split_list(_field(doc.first("seen"), 1)):
		_seen.append([pair.get_slice("=", 0), pair.get_slice("=", 1).to_int()])
	_achievements.assign(_split_list(_field(doc.first("ach"), 1)))
	for pair in _split_list(_field(doc.first("achat"), 1)):
		_achieved_at[pair.get_slice("=", 0)] = pair.get_slice("=", 1).to_int()
	for pair in _split_list(_field(doc.first("stat"), 1)):
		_stats.append([pair.get_slice("=", 0), pair.get_slice("=", 1).to_int()])


func _write_dirty() -> void:
	for kind: String in _dirty:
		if kind == "open" and not doc.records_of("unlock").is_empty():  # in the older lines' place
			doc.replace_kind("open", [] as Array[PackedStringArray])
			doc.replace_kind("unlock", _records_for(kind))
			continue
		if kind == "spec":
			continue
		doc.replace_kind(kind, _records_for(kind))
		if kind == "ach":
			doc.replace_kind("achat", _records_for("achat"))
	if _dirty.has("spec"):  # after the talent records, as the game writes them (exe 0x87d56d2)
		doc.replace_kind("spec", _records_for("spec"), "talent")
	_dirty.clear()


func _records_for(kind: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	match kind:
		"hero":
			for c in heroes:
				out.append(heroes[c])
		"open":
			for c in opened:
				for zone: String in opened[c]:
					out.append(PackedStringArray(["open", str(c), zone]))
		"beat":
			for b in _beaten:
				out.append(PackedStringArray(["beat", str(b[0]), b[1]]))
		"talent":
			for c in _talent_order:
				out.append(PackedStringArray(["talent", str(c), str(_talents[c]["xp"]), _ranks_text(_talents[c]["ranks"])]))
		"spec":  # spec|{class}|{lit}|{b0}|{b1}|{b2}, every build written, empty or not
			for c: int in _specs:
				var line := PackedStringArray(["spec", str(c), str(_specs[c]["lit"])])
				for build: Array in _specs[c]["builds"]:
					line.append(_ranks_text(build))
				out.append(line)
		"items":
			out.append(PackedStringArray(["items", ",".join(_items.map(func(i: int) -> String: return str(i)))]))
		"seen":
			out.append(PackedStringArray(["seen", _join_pairs(_seen, "=")]))
		"ach":
			out.append(PackedStringArray(["ach", ",".join(_achievements)]))
		"achat":
			var pairs := PackedStringArray()
			for key in _achievements:
				pairs.append("%s=%d" % [key, _achieved_at.get(key, 0)])
			out.append(PackedStringArray(["achat", ",".join(pairs)]))
		"stat":
			out.append(PackedStringArray(["stat", _join_pairs(_stats, "=")]))
	return out


func _talent_entry(class_id: int) -> Dictionary:
	if not _talents.has(class_id):
		_talents[class_id] = {"xp": 0, "ranks": []}
		_talent_order.append(class_id)
	return _talents[class_id]


static func _field(record: PackedStringArray, index: int) -> String:
	return record[index] if record.size() > index else ""


## A ranks list as saved: id:rank,id:rank…
static func _parse_ranks(text: String) -> Array:
	var ranks := []
	for pair in _split_list(text):
		ranks.append([pair.get_slice(":", 0), pair.get_slice(":", 1).to_int()])
	return ranks


static func _ranks_text(pairs: Array) -> String:
	var parts := PackedStringArray()
	for pair: Array in pairs:
		parts.append("%s:%d" % pair)
	return ",".join(parts)


## Whether a field parses as a u8, as Rust's does: digits with an optional leading "+", 0 … 255.
static func _is_u8(field: String) -> bool:
	var digits := field.trim_prefix("+")
	if digits.is_empty():
		return false
	for ch in digits:
		if ch < "0" or ch > "9":
			return false
	var significant := digits.lstrip("0")
	return significant.length() <= 3 and significant.to_int() <= 255


static func _split_list(text: String) -> PackedStringArray:
	return text.split(",", false)


static func _join_pairs(pairs: Array, separator: String) -> String:
	var parts := PackedStringArray()
	for pair in pairs:
		parts.append("%s%s%d" % [pair[0], separator, pair[1]])
	return ",".join(parts)
