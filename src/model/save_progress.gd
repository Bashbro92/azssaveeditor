class_name SaveProgress
extends RefCounted
## Typed, editable view of a save's progression records over a SaveDoc.
##
## Understands: hero, unlock, beat, talent, items, seen, ach, achat, stat. Every other record (pick,
## equip, look, perk, tabard, pets, resets, unknown kinds) is left untouched. Only record kinds that
## were changed are rewritten, so an unedited save writes back byte for byte.
## Classes are WoW class ids (1 warrior … 11 druid), as stored in the save.

const MAX_RARITY := 4  # 0 Common … 4 Legendary
const MIN_ZONES_OPEN := 1
## Talent XP curve, from the game's talents view (exe 0x1402c9de1): point n costs 65 + 15·n XP
## (80, 95, 110 … 830), for MAX_TALENT_POINTS points. Verified against a real save.
const MAX_TALENT_POINTS := 51
const _POINT_COST_BASE := 65
const _POINT_COST_STEP := 15
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
var unlocked: Dictionary = {}      # class -> zones open
var _beaten: Array = []            # [class, zone id] in save order
var _talents: Dictionary = {}      # class -> {"xp": int, "ranks": Array of [id, rank]}
var _talent_order: Array[int] = []
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


## Zones open to a class. A class without an unlock record has only its first zone open.
func zones_unlocked(class_id: int) -> int:
	return unlocked.get(class_id, MIN_ZONES_OPEN)


## Sets the zones open to a class, clamped to MIN_ZONES_OPEN..zone_count.
func set_zones_unlocked(class_id: int, count: int, zone_count: int) -> void:
	var clamped := clampi(count, MIN_ZONES_OPEN, maxi(MIN_ZONES_OPEN, zone_count))
	if zones_unlocked(class_id) != clamped:
		unlocked[class_id] = clamped
		_dirty["unlock"] = true


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
	set_zones_unlocked(class_id, zones.size(), zones.size())


## No zone won by a class, back to only its first zone open.
func clear_zones(class_id: int, zones: PackedStringArray) -> void:
	set_beaten_for(class_id, zones, false)
	set_zones_unlocked(class_id, MIN_ZONES_OPEN, zones.size())


# ---------------------------------------------------------------- talents

func talent_xp(class_id: int) -> int:
	return _talents.get(class_id, {}).get("xp", 0)


func set_talent_xp(class_id: int, xp: int) -> void:
	if talent_xp(class_id) == xp:
		return
	_talent_entry(class_id)["xp"] = maxi(0, xp)
	_dirty["talent"] = true


func talent_rank(class_id: int, talent_id: String) -> int:
	for pair in _talents.get(class_id, {}).get("ranks", []):
		if pair[0] == talent_id:
			return pair[1]
	return 0


func set_talent_rank(class_id: int, talent_id: String, rank: int) -> void:
	if talent_rank(class_id, talent_id) == rank:
		return
	var ranks: Array = _talent_entry(class_id)["ranks"]
	for i in range(ranks.size()):
		if ranks[i][0] == talent_id:
			if rank > 0:
				ranks[i][1] = rank
			else:
				ranks.remove_at(i)
			_dirty["talent"] = true
			return
	ranks.append([talent_id, rank])
	_dirty["talent"] = true


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


func talent_points_spent(class_id: int) -> int:
	var spent := 0
	for pair in _talents.get(class_id, {}).get("ranks", []):
		spent += pair[1]
	return spent


## Points spent in one tree; `talents` are the tree's talent dictionaries (id, ranks, row, col).
func tree_points_spent(class_id: int, talents: Array) -> int:
	var spent := 0
	for t: Dictionary in talents:
		spent += talent_rank(class_id, t["id"])
	return spent


## Fills a tree row by row (as the game unlocks rows) up to each talent's max rank, without the
## class going over MAX_TALENT_POINTS. Raises talent XP to FULL_TALENT_XP so the points are earned.
func max_tree(class_id: int, talents: Array) -> void:
	var budget := MAX_TALENT_POINTS - (talent_points_spent(class_id) - tree_points_spent(class_id, talents))
	var ordered := talents.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [int(a["row"]), int(a["col"])] < [int(b["row"]), int(b["col"])])
	for t: Dictionary in ordered:
		var rank := clampi(int(t["ranks"]), 0, maxi(budget, 0))
		set_talent_rank(class_id, t["id"], rank)
		budget -= rank
	set_talent_xp(class_id, maxi(talent_xp(class_id), FULL_TALENT_XP))


func reset_tree(class_id: int, talents: Array) -> void:
	for t: Dictionary in talents:
		set_talent_rank(class_id, t["id"], 0)


## Removes every spent rank of a class; its talent XP is kept.
func reset_talents(class_id: int) -> void:
	if talent_points_spent(class_id) == 0:
		return
	_talent_entry(class_id)["ranks"] = []
	_dirty["talent"] = true


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
		unlocked[r[1].to_int()] = r[2].to_int()
	for r in doc.records_of("beat"):
		_beaten.append([r[1].to_int(), r[2]])
	for r in doc.records_of("talent"):
		var ranks := []
		for pair in _split_list(r[3] if r.size() > 3 else ""):
			ranks.append([pair.get_slice(":", 0), pair.get_slice(":", 1).to_int()])
		_talents[r[1].to_int()] = {"xp": r[2].to_int(), "ranks": ranks}
		_talent_order.append(r[1].to_int())
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
		doc.replace_kind(kind, _records_for(kind))
		if kind == "ach":
			doc.replace_kind("achat", _records_for("achat"))
	_dirty.clear()


func _records_for(kind: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	match kind:
		"hero":
			for c in heroes:
				out.append(heroes[c])
		"unlock":
			for c in unlocked:
				out.append(PackedStringArray(["unlock", str(c), str(unlocked[c])]))
		"beat":
			for b in _beaten:
				out.append(PackedStringArray(["beat", str(b[0]), b[1]]))
		"talent":
			for c in _talent_order:
				var ranks := PackedStringArray()
				for pair in _talents[c]["ranks"]:
					ranks.append("%s:%d" % pair)
				out.append(PackedStringArray(["talent", str(c), str(_talents[c]["xp"]), ",".join(ranks)]))
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


static func _split_list(text: String) -> PackedStringArray:
	return text.split(",", false)


static func _join_pairs(pairs: Array, separator: String) -> String:
	var parts := PackedStringArray()
	for pair in pairs:
		parts.append("%s%s%d" % [pair[0], separator, pair[1]])
	return ",".join(parts)
