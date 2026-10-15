class_name CodexPanel
extends EditorPanel
## Highest rarity seen for every ring, trinket and amulet, and for each spell's legendary amulet.
## Each section, and the whole codex, can be set to one rarity at once.

var _rarities := PackedStringArray()


func build() -> void:
	_rarities = PackedStringArray(["Not seen"])
	for i in range(SaveProgress.MAX_RARITY + 1):
		_rarities.append(session.game.text.get("rarity.%d" % i, str(i)))

	var sections := _sections()
	var everything := PackedStringArray()
	for section in sections:
		everything.append_array(section["entries"])
	content.add_child(_bulk_bar("Whole codex:", everything))

	for section in sections:
		content.add_child(_heading(section["title"]))
		content.add_child(_bulk_bar("Set section:", section["entries"]))
		var grid := GridContainer.new()
		grid.columns = 3
		content.add_child(grid)
		for row: Array in section["rows"]:
			_add_row(grid, row[0], row[1], row[2])


## Sections as {title, entries: codex ids, rows: [id, icon, name]}.
func _sections() -> Array[Dictionary]:
	var sections: Array[Dictionary] = [_section("Rings, trinkets and amulets")]
	for entry in session.game.jewels + session.game.amulets:
		_add_entry(sections[0], entry["id"], entry["icon"], entry["name"])
	for c in session.game.classes:
		var section := _section("Legendary amulets: " + c["name"])
		for spell: String in c["spell_pool"]:
			var ability: Dictionary = session.game.abilities.get(spell, {})
			_add_entry(section, "legendary:" + spell, ability.get("icon", ""), ability.get("name", spell))
		sections.append(section)
	return sections


static func _section(title: String) -> Dictionary:
	return {"title": title, "entries": PackedStringArray(), "rows": []}


static func _add_entry(section: Dictionary, entry_id: String, icon_name: String, title: String) -> void:
	section["entries"].append(entry_id)
	section["rows"].append([entry_id, icon_name, title])


func _bulk_bar(label: String, entries: PackedStringArray) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_child(_label(label))
	var choice := _rarity_choice(SaveProgress.MAX_RARITY)
	bar.add_child(choice)
	bar.add_child(_button("Apply", func() -> void:
		var rarity := choice.selected - 1
		_apply_bulk(func() -> void: session.progress.set_seen_rarity_for(entries, rarity))))
	return bar


func _add_row(grid: GridContainer, entry_id: String, icon_name: String, title: String) -> void:
	var p := session.progress
	grid.add_child(_icon(icon_name))
	grid.add_child(_label(title, 260))
	var choice := _rarity_choice(p.seen_rarity(entry_id))
	choice.item_selected.connect(func(i: int) -> void:
		p.set_seen_rarity(entry_id, i - 1)
		session.mark_edited())
	grid.add_child(choice)


## Rarity picker: index 0 is "Not seen" (-1), then Common (0) … Legendary.
func _rarity_choice(rarity: int) -> OptionButton:
	var choice := OptionButton.new()
	for r in _rarities:
		choice.add_item(r)
	choice.select(rarity + 1)
	return choice
