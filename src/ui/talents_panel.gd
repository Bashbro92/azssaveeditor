class_name TalentsPanel
extends EditorPanel
## Talent XP and spent ranks of one class, its three trees side by side. Each tree can be maxed
## (within the 51-point budget) or reset, and all ranks of the class can be reset at once. For every
## class at once: max talent XP, reset spent points, or clear both.

var _selected := 0
var _trees_box: VBoxContainer
var _points_label: Label


func build() -> void:
	var p := session.progress
	var class_ids: Array[int] = []
	for c in session.game.classes:
		class_ids.append(int(c["wow_class_id"]))
	var all_bar := HBoxContainer.new()
	all_bar.add_child(_label("All classes:"))
	all_bar.add_child(_button("Max XP", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.set_talent_xp(id, SaveProgress.FULL_TALENT_XP))))
	all_bar.add_child(_button("Reset talents", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.reset_talents(id))))
	all_bar.add_child(_button("Clear all", func() -> void: _apply_bulk(func() -> void:
		for id in class_ids:
			p.reset_talents(id)
			p.set_talent_xp(id, 0))))
	content.add_child(all_bar)

	var picker := _class_picker(_show_class)
	picker.select(_selected)
	content.add_child(picker)
	_trees_box = VBoxContainer.new()
	content.add_child(_trees_box)
	_show_class(session.game.classes[_selected])


func _show_class(c: Dictionary) -> void:
	_selected = session.game.classes.find(c)
	for child in _trees_box.get_children():
		child.queue_free()
	var p := session.progress
	var class_id := int(c["wow_class_id"])

	var class_row := HBoxContainer.new()
	class_row.add_child(_label("Talent XP"))
	class_row.add_child(_spin(p.talent_xp(class_id), SaveProgress.FULL_TALENT_XP, func(v: int) -> void:
		p.set_talent_xp(class_id, v)
		_update_points(class_id), 120))
	_points_label = _label("")
	class_row.add_child(_points_label)
	class_row.add_child(_button("Reset talents", func() -> void: _apply_bulk(func() -> void: p.reset_talents(class_id))))
	_trees_box.add_child(class_row)
	_update_points(class_id)

	var trees_row := HBoxContainer.new()
	trees_row.add_theme_constant_override("separation", 24)
	_trees_box.add_child(trees_row)
	for tree in session.game.trees_for_class(c["id"]):
		var talents: Array = tree["talents"]
		var column := VBoxContainer.new()
		var header := HBoxContainer.new()
		header.add_child(_icon(tree["icon"], 24))
		header.add_child(_heading("%s (%d)" % [tree["name"], p.tree_points_spent(class_id, talents)]))
		header.add_child(_button("Max", func() -> void: _apply_bulk(func() -> void: p.max_tree(class_id, talents))))
		header.add_child(_button("Reset", func() -> void: _apply_bulk(func() -> void: p.reset_tree(class_id, talents))))
		column.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 3
		for t: Dictionary in talents:
			var talent_id: String = t["id"]
			var name_label := _label(t["name"])
			name_label.tooltip_text = t.get("description", "")
			name_label.mouse_filter = Control.MOUSE_FILTER_PASS
			grid.add_child(_icon(t["icon"], 24))
			grid.add_child(name_label)
			grid.add_child(_spin(p.talent_rank(class_id, talent_id), int(t["ranks"]), func(v: int) -> void:
				p.set_talent_rank(class_id, talent_id, v)
				_update_points(class_id), 70))
		column.add_child(grid)
		trees_row.add_child(column)


func _update_points(class_id: int) -> void:
	var p := session.progress
	var spent := p.talent_points_spent(class_id)
	var earned := p.talent_points_earned(class_id)
	_points_label.text = "Points: %d spent / %d earned (max %d)" % [spent, earned, SaveProgress.MAX_TALENT_POINTS]
	_points_label.modulate = Color(1, 0.55, 0.45) if spent > earned else Color.WHITE
	_points_label.tooltip_text = "More points spent than earned: raise talent XP or remove ranks." \
			if spent > earned else ""
