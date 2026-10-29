class_name ZonesPanel
extends EditorPanel
## Per class: how many zones are open, which zones were won, and the highest Heroic tier beaten in each zone.
## All classes, or one class, can be opened, won, difficulty-unlocked or cleared at once. Like the game, reading a
## save opens the zone after each normal win; Heroic V in `hbeat` makes every difficulty available.


func build() -> void:
	var p := session.progress
	var zones := session.game.zones
	var zone_ids := session.game.zone_ids()
	var zone_count := zones.size()
	var class_ids: Array[int] = []
	for c in session.game.classes:
		class_ids.append(int(c["wow_class_id"]))

	content.add_child(_label(("Zones open per class (%d to %d), and which zones each class has won. When the game "
			+ "loads the save, it opens the zone after each won one.") % [SaveProgress.MIN_ZONES_OPEN, zone_count]))
	var bar := HBoxContainer.new()
	bar.add_child(_label("All classes:"))
	bar.add_child(_button("Open all", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.set_zones_unlocked(id, zone_count))))
	bar.add_child(_button("Win all", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.win_all_zones(id))))
	bar.add_child(_button("Unlock all difficulties", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.unlock_all_zone_difficulties(id))))
	bar.add_child(_button("Clear all", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.clear_zones(id))))
	content.add_child(bar)

	var grid := GridContainer.new()
	grid.columns = 3 + zone_count
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_child(_label("Class", 120))
	grid.add_child(_label("Zones open"))
	for z in zones:
		grid.add_child(_label(z["name"]))
	grid.add_child(_label("Wins"))
	for c in session.game.classes:
		var class_id := int(c["wow_class_id"])
		grid.add_child(_label(c["name"], 120))
		grid.add_child(_spin(p.zones_unlocked(class_id), zone_count,
				func(v: int) -> void: p.set_zones_unlocked(class_id, v), 70, SaveProgress.MIN_ZONES_OPEN))
		for zone_id in zone_ids:
			grid.add_child(_check("", p.is_beaten(class_id, zone_id),
					func(on: bool) -> void: p.set_beaten(class_id, zone_id, on)))
		var row_buttons := HBoxContainer.new()
		row_buttons.add_child(_button("Win all", func() -> void:
			_apply_bulk(func() -> void: p.win_all_zones(class_id))))
		row_buttons.add_child(_button("Clear", func() -> void:
			_apply_bulk(func() -> void: p.clear_zones(class_id))))
		grid.add_child(row_buttons)
	content.add_child(grid)

	content.add_child(_label("Highest Heroic tier beaten per zone (0 = none, 5 = Heroic I–V unlocked):"))
	var heroic_grid := GridContainer.new()
	heroic_grid.columns = 1 + zone_count + 1
	heroic_grid.add_theme_constant_override("h_separation", 10)
	heroic_grid.add_child(_label("Class", 120))
	for z in zones:
		heroic_grid.add_child(_label(z["name"]))
	heroic_grid.add_child(_label("Difficulties"))
	for c in session.game.classes:
		var class_id := int(c["wow_class_id"])
		heroic_grid.add_child(_label(c["name"], 120))
		for zone_id in zone_ids:
			heroic_grid.add_child(_spin(p.heroic_level(class_id, zone_id), SaveProgress.MAX_HEROIC_LEVEL,
					func(v: int) -> void: p.set_heroic_level(class_id, zone_id, v), 58, 0))
		var row_buttons := HBoxContainer.new()
		row_buttons.add_child(_button("Unlock all", func() -> void:
			_apply_bulk(func() -> void: p.unlock_all_zone_difficulties(class_id))))
		heroic_grid.add_child(row_buttons)
	content.add_child(heroic_grid)
