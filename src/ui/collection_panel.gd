class_name CollectionPanel
extends EditorPanel
## Gear collection of one class: every slot (rows) in every tier (columns). Collect or clear all
## gear of the selected class, or of every class.

var _selected := 0
var _grid_box: VBoxContainer


func build() -> void:
	var p := session.progress
	var all_items := PackedInt32Array()
	for c in session.game.classes:
		all_items.append_array(session.game.item_ids_for_class(c["id"], int(c["wow_class_id"])))
	var all_bar := HBoxContainer.new()
	all_bar.add_child(_label("All classes:"))
	all_bar.add_child(_button("Collect all", func() -> void: _apply_bulk(func() -> void: p.set_items(all_items, true))))
	all_bar.add_child(_button("Clear all", func() -> void: _apply_bulk(func() -> void: p.set_items(all_items, false))))
	content.add_child(all_bar)

	var picker := _class_picker(_show_class)
	picker.select(_selected)
	content.add_child(picker)
	_grid_box = VBoxContainer.new()
	content.add_child(_grid_box)
	_show_class(session.game.classes[_selected])


func _show_class(c: Dictionary) -> void:
	_selected = session.game.classes.find(c)
	for child in _grid_box.get_children():
		child.queue_free()
	var p := session.progress
	var class_id := int(c["wow_class_id"])
	var items := session.game.item_ids_for_class(c["id"], class_id)

	var buttons := HBoxContainer.new()
	buttons.add_child(_label("This class:"))
	buttons.add_child(_button("Collect all", func() -> void: _apply_bulk(func() -> void: p.set_items(items, true))))
	buttons.add_child(_button("Clear all", func() -> void: _apply_bulk(func() -> void: p.set_items(items, false))))
	_grid_box.add_child(buttons)

	var grid := GridContainer.new()
	grid.columns = GameData.GEAR_TIERS
	grid.add_theme_constant_override("h_separation", 16)
	for item in items:  # ordered slot by slot, tiers within a slot
		grid.add_child(_check(session.game.item_name(item), p.has_item(item),
				func(on: bool) -> void: p.set_item(item, on)))
	_grid_box.add_child(grid)
