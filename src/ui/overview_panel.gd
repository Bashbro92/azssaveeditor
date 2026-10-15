class_name OverviewPanel
extends EditorPanel
## Heroes in the save and the lifetime stats.

const _STATS: Array[String] = ["kills", "gold", "guardians", "bosses", "runs", "wins", "caches"]
const _GENDER := ["male", "female"]
## WoW race id (as stored in hero records) -> race key in the game text.
const _RACE_KEY := {1: "human", 2: "orc", 3: "dwarf", 4: "nightelf", 5: "scourge", 6: "tauren", 7: "gnome", 8: "troll"}


func build() -> void:
	var p := session.progress
	content.add_child(_heading("Heroes"))
	var heroes := GridContainer.new()
	heroes.columns = 2
	for class_id in p.hero_classes():
		var record: PackedStringArray = p.heroes[class_id]
		var c := session.game.class_by_wow_id(class_id)
		heroes.add_child(_icon(c.get("icon", "")))
		var race_id := record[2].to_int() if record.size() > 2 else 0
		var race: String = session.game.text.get("race.%s.name" % _RACE_KEY.get(race_id, ""), "race %d" % race_id)
		var gender: String = _GENDER[record[3].to_int()] if record.size() > 3 and record[3].to_int() < 2 else ""
		heroes.add_child(_label("%s  (%s, %s)" % [class_name_of(class_id), race, gender]))
	content.add_child(heroes)

	content.add_child(_heading("Lifetime stats"))
	var stats := GridContainer.new()
	stats.columns = 2
	for stat_name in _STATS:
		stats.add_child(_label(stat_name.capitalize(), 120))
		stats.add_child(_spin(p.stat(stat_name), 100000000, func(v: int) -> void: p.set_stat(stat_name, v), 140))
	content.add_child(stats)
