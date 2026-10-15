class_name EditorPanel
extends ScrollContainer
## Base for the editor's tabs: rebuilds its content from the session's open save on every reload.

const _MARGIN := 12
const _PICKER_ICON := 24

var session: EditorSession
var content := VBoxContainer.new()


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, _MARGIN)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	add_child(margin)


func bind(editor_session: EditorSession) -> void:
	session = editor_session
	session.save_changed.connect(reload)
	reload()


func reload() -> void:
	for child in content.get_children():
		child.queue_free()
	if session == null or not session.is_configured() or not session.has_save():
		content.add_child(_label("Open a save to edit it."))
		return
	build()


## Override: add controls for the open save to `content`.
func build() -> void:
	pass


func class_name_of(wow_class_id: int) -> String:
	var c := session.game.class_by_wow_id(wow_class_id)
	return c.get("name", "Class %d" % wow_class_id)


func _label(text: String, min_width: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = min_width
	return label


func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _icon(icon_name: String, edge: int = 32) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = session.icons.get_icon(icon_name)
	rect.custom_minimum_size = Vector2(edge, edge)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


## A spin box limited to min_value..max_value (typed input is clamped to the range too).
func _spin(value: int, max_value: int, on_change: Callable, width: int = 90, min_value: int = 0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.allow_lesser = false
	spin.allow_greater = false
	spin.rounded = true
	spin.custom_minimum_size.x = width
	spin.set_value_no_signal(value)
	spin.value_changed.connect(func(v: float) -> void:
		on_change.call(int(v))
		session.mark_edited())
	return spin


func _check(text: String, pressed: bool, on_toggle: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.set_pressed_no_signal(pressed)
	box.toggled.connect(func(on: bool) -> void:
		on_toggle.call(on)
		session.mark_edited())
	return box


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	return button


## Applies a bulk edit, marks the save edited and rebuilds the panel so every control shows it.
func _apply_bulk(edit: Callable) -> void:
	edit.call()
	session.mark_edited()
	reload()


## A class picker; calls on_select with the chosen class dictionary and once for the first class.
func _class_picker(on_select: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_theme_constant_override("icon_max_width", _PICKER_ICON)
	picker.get_popup().add_theme_constant_override("icon_max_width", _PICKER_ICON)
	picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for c in session.game.classes:
		picker.add_icon_item(session.icons.get_icon(c["icon"]), c["name"])
	picker.item_selected.connect(func(i: int) -> void: on_select.call(session.game.classes[i]))
	return picker
