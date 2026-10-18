class_name TalentsPanel
extends EditorPanel
## Talent XP and spent ranks of one class, its three trees side by side. Each class has three specs
## (talent builds); the lit one is what runs play with. Any spec can be shown and edited, and made the
## lit one. Each tree can be maxed (within the 51-point budget) or reset, and all ranks of the spec can
## be reset at once. For every class at once (lit specs): max talent XP, reset spent points, or clear both.

const _LIT_COLOR := Color(1, 0.82, 0.3)

var _selected := 0
var _shown_spec := {}  # class id -> the spec shown, the lit one until another is picked
var _shown_for: SaveProgress  # the save _shown_spec is for
var _trees_box: VBoxContainer
var _points_label: Label


func build() -> void:
	var p := session.progress
	if p != _shown_for:
		_shown_spec.clear()
		_shown_for = p
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
	var spec: int = _shown_spec.get(class_id, p.lit_spec(class_id))
	var trees := session.game.trees_for_class(c["id"])
	_trees_box.add_child(_spec_row(c, spec, trees))

	var class_row := HBoxContainer.new()
	class_row.add_child(_label("Talent XP"))
	class_row.add_child(_spin(p.talent_xp(class_id), SaveProgress.FULL_TALENT_XP, func(v: int) -> void:
		p.set_talent_xp(class_id, v)
		_update_points(class_id), 120))
	_points_label = _label("")
	class_row.add_child(_points_label)
	class_row.add_child(_button("Reset talents", func() -> void: _apply_bulk(func() -> void:
		p.reset_talents(class_id, spec))))
	_trees_box.add_child(class_row)
	_update_points(class_id)

	var trees_row := HBoxContainer.new()
	trees_row.add_theme_constant_override("separation", 24)
	_trees_box.add_child(trees_row)
	for tree in trees:
		var talents: Array = tree["talents"]
		var column := VBoxContainer.new()
		var header := HBoxContainer.new()
		header.add_child(_icon(tree["icon"], 24))
		header.add_child(_heading("%s (%d)" % [tree["name"], p.tree_points_spent(class_id, talents, spec)]))
		header.add_child(_button("Max", func() -> void: _apply_bulk(func() -> void: p.max_tree(class_id, talents, spec))))
		header.add_child(_button("Reset", func() -> void: _apply_bulk(func() -> void:
			p.reset_tree(class_id, talents, spec))))
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
			grid.add_child(_spin(p.talent_rank(class_id, talent_id, spec), int(t["ranks"]), func(v: int) -> void:
				p.set_talent(class_id, t, v, spec)
				if t.get("excludes", []).is_empty():
					_update_points(class_id)
				else:
					_show_class(c), 70))  # an excluded talent may have been unlearned
		column.add_child(grid)
		trees_row.add_child(column)


## Spec 1 to 3 of a class, the lit one in gold, each with its points per tree; the shown one can be made lit.
func _spec_row(c: Dictionary, spec: int, trees: Array[Dictionary]) -> HBoxContainer:
	var p := session.progress
	var class_id := int(c["wow_class_id"])
	var row := HBoxContainer.new()
	row.add_child(_label("Spec"))
	var group := ButtonGroup.new()
	for i in range(SaveProgress.SPECS):
		var lit := i == p.lit_spec(class_id)
		var button := _button("Spec %d%s" % [i + 1, " (lit)" if lit else ""], func() -> void:
			_shown_spec[class_id] = i
			_show_class(c))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(i == spec)
		if lit:
			button.add_theme_color_override("font_color", _LIT_COLOR)
			button.add_theme_color_override("font_pressed_color", _LIT_COLOR)
			button.add_theme_color_override("font_hover_color", _LIT_COLOR)
		var per_tree := PackedStringArray()
		for tree in trees:
			per_tree.append(str(p.tree_points_spent(class_id, tree["talents"], i)))
		button.tooltip_text = ("Empty" if p.talent_points_spent(class_id, i) == 0 else "/".join(per_tree)) \
				+ ("\nLit: runs play with this spec." if lit else "")
		row.add_child(button)
	var make_lit := _button("Make lit", func() -> void:
		if p.switch_spec(class_id, spec, trees):
			_shown_spec.erase(class_id)
			session.mark_edited()
			_show_class(c))
	make_lit.disabled = spec == p.lit_spec(class_id)
	make_lit.tooltip_text = "Switch to this spec as the game does: the lit spec keeps its ranks, and this " \
			+ "spec's ranks become the talents runs play with, relearned within the points earned."
	row.add_child(make_lit)
	return row


func _update_points(class_id: int) -> void:
	var p := session.progress
	var spec: int = _shown_spec.get(class_id, p.lit_spec(class_id))
	var spent := p.talent_points_spent(class_id, spec)
	var earned := p.talent_points_earned(class_id)
	_points_label.text = "Points: %d spent / %d earned (max %d)" % [spent, earned, SaveProgress.MAX_TALENT_POINTS]
	_points_label.modulate = Color(1, 0.55, 0.45) if spent > earned else Color.WHITE
	_points_label.tooltip_text = "More points spent than earned: raise talent XP or remove ranks." \
			if spent > earned else ""
