class_name AchievementsPanel
extends EditorPanel
## Achievements with their in-game names and icons, grouped as in the game data. Every group (and all
## of them) can be earned or cleared at once. Keys in the save that the game data doesn't know are
## listed under Other so nothing is hidden.

const _OTHER := "Other"


func build() -> void:
	var p := session.progress
	var groups := _groups()
	var everything := PackedStringArray()
	for title: String in groups:
		for a: Dictionary in groups[title]:
			everything.append(a["key"])
	content.add_child(_bulk_bar("All achievements:", everything))

	var now := int(Time.get_unix_time_from_system())
	for title: String in groups:
		var keys := PackedStringArray()
		for a: Dictionary in groups[title]:
			keys.append(a["key"])
		var earned := 0
		for key in keys:
			earned += 1 if p.has_achievement(key) else 0
		content.add_child(_heading("%s (%d / %d)" % [title, earned, keys.size()]))
		content.add_child(_bulk_bar("Section:", keys))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 8)
		for a: Dictionary in groups[title]:
			var key: String = a["key"]
			var tip := "%s\n%s" % [a.get("description", ""), key]
			var icon := _icon(a.get("icon", ""), 24)
			icon.tooltip_text = tip
			var box := _check(a.get("name", key), p.has_achievement(key),
					func(on: bool) -> void: p.set_achievement(key, on, now))
			box.tooltip_text = tip
			box.custom_minimum_size.x = 230
			grid.add_child(icon)
			grid.add_child(box)
		content.add_child(grid)


## Group title -> achievement dictionaries (key, name, description, icon), in game-data order.
func _groups() -> Dictionary:
	var groups := {}
	var known := {}
	for a in session.game.achievements:
		var title: String = a.get("group", _OTHER)
		if not groups.has(title):
			groups[title] = []
		groups[title].append(a)
		known[a["key"]] = true
	for key in session.progress.achievements():
		if not known.has(key):
			if not groups.has(_OTHER):
				groups[_OTHER] = []
			groups[_OTHER].append({"key": key, "name": key})
	return groups


func _bulk_bar(label: String, keys: PackedStringArray) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_child(_label(label))
	for earned in [true, false]:
		bar.add_child(_button("Earn all" if earned else "Clear all", func() -> void:
			var now := int(Time.get_unix_time_from_system())
			_apply_bulk(func() -> void: session.progress.set_achievements(keys, earned, now))))
	return bar
