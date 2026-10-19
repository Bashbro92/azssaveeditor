class_name PerksPanel
extends EditorPanel
## The account's perks and perk resets, the tabards bought with perk points and the pickup companions' looks.
## The game checks none of these against the achievement points they cost.

const _MOST_RESETS := 2  ## the game allows two perk resets
const _DEFAULT := "Default"


func build() -> void:
	var p := session.progress
	var perks := session.game.perks
	content.add_child(_heading("Perks"))
	var bar := HBoxContainer.new()
	bar.add_child(_button("Learn all", func() -> void: _apply_bulk(func() -> void:
		for perk in perks:
			p.set_perk_rank(perk["id"], perk["costs"].size()))))
	bar.add_child(_button("Unlearn all", func() -> void: _apply_bulk(func() -> void:
		for perk_id: String in p.perks():
			p.set_perk_rank(perk_id, 0))))
	content.add_child(bar)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	var known := {}
	for perk in perks:
		var perk_id: String = perk["id"]
		known[perk_id] = true
		grid.add_child(_icon(perk["icon"], 24))
		grid.add_child(_label(perk["name"], 200))
		grid.add_child(_spin(p.perks().get(perk_id, 0), perk["costs"].size(),
				func(v: int) -> void: p.set_perk_rank(perk_id, v), 70))
		grid.add_child(_label(_needs(perk)))
	for perk_id: String in p.perks():  # perks the game data doesn't know, so nothing is hidden
		if not known.has(perk_id):
			grid.add_child(_icon("", 24))
			grid.add_child(_label(perk_id, 200))
			grid.add_child(_spin(p.perks()[perk_id], 255, func(v: int) -> void: p.set_perk_rank(perk_id, v), 70))
			grid.add_child(_label(""))
	content.add_child(grid)
	var resets := HBoxContainer.new()
	resets.add_child(_label("Perk resets used (of %d):" % _MOST_RESETS))
	resets.add_child(_spin(p.perk_resets(), _MOST_RESETS, func(v: int) -> void: p.set_perk_resets(v), 70))
	content.add_child(resets)

	content.add_child(_heading("Tabards bought"))
	content.add_child(_label("Tabards that come with an achievement aren't saved; earn the achievement instead."))
	var tabards := GridContainer.new()
	tabards.columns = 4
	for t in session.game.tabards:
		if t["unlock"] != "":
			continue
		var tabard_id: int = t["id"]
		tabards.add_child(_icon(t["icon"], 24))
		var box := _check("%s (%d)" % [t["name"], t["cost"]], p.tabards().has(tabard_id),
				func(on: bool) -> void: p.set_tabard(tabard_id, on))
		box.custom_minimum_size.x = 280
		tabards.add_child(box)
	content.add_child(tabards)

	content.add_child(_heading("Companion looks"))
	content.add_child(_label("A look its achievement hasn't unlocked shows as the default in game."))
	var looks := p.companion_looks()
	var slots := HBoxContainer.new()
	for slot in range(2):
		slots.add_child(_label("Companion %d:" % (slot + 1)))
		slots.add_child(_look_choice(looks, slot))
	content.add_child(slots)


## "Needs <achievement>" (and the perk it needs first) for a perk's row.
func _needs(perk: Dictionary) -> String:
	var parts := PackedStringArray()
	if perk["requires"] != "":
		parts.append(_achievement_name(perk["requires"]))
	if perk["requires_perk"] != "":
		for other in session.game.perks:
			if other["id"] == perk["requires_perk"]:
				parts.append(other["name"])
	return "Needs " + ", ".join(parts) if not parts.is_empty() else ""


func _achievement_name(key: String) -> String:
	for a in session.game.achievements:
		if a["key"] == key:
			return a["name"]
	return key


## A picker for companion `slot`'s look: the default, then every look the game has (and the saved one if the game
## doesn't know it). The save keeps the chosen looks in slot order, defaults left out.
func _look_choice(looks: Array[String], slot: int) -> OptionButton:
	var ids: Array[String] = [""]
	var choice := OptionButton.new()
	choice.add_item(_DEFAULT)
	for look in session.game.companion_looks:
		ids.append(look["id"])
		var unlock: String = look["unlock"]
		choice.add_icon_item(session.icons.get_icon(look["icon"]),
				look["name"] + ("" if unlock == "" else "  (" + _achievement_name(unlock) + ")"))
	var current: String = looks[slot] if slot < looks.size() else ""
	if not ids.has(current):
		ids.append(current)
		choice.add_item(current)
	choice.select(ids.find(current))
	choice.item_selected.connect(func(i: int) -> void:
		var chosen := looks.duplicate()
		chosen.resize(2)
		chosen[slot] = ids[i]
		_apply_bulk(func() -> void: session.progress.set_companion_looks(chosen)))
	return choice
