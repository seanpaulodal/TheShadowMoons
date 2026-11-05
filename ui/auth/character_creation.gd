extends Control
## Character creation: name, one of nine classes, basic appearance.
## The UI is built in code. Class texts and appearance counts are placeholders
## until the real class data and 3D models exist.

# Placeholder number of choices per appearance slot.
const APPEARANCE_COUNTS := {"body": 3, "hair": 6, "face": 6, "skin": 6}

# Placeholder descriptions. Replace with real class data in a later milestone.
const CLASS_BLURBS := {
	"warrior": "Frontline melee fighter. (placeholder)",
	"mage": "Ranged spellcaster. (placeholder)",
	"archer": "Ranged physical attacker. (placeholder)",
	"rogue": "Fast melee attacker. (placeholder)",
	"gunner": "Firearm specialist. (placeholder)",
	"extreme": "Description coming soon.",
	"brawler": "Close-combat fighter. (placeholder)",
	"healer": "Support and recovery. (placeholder)",
	"necromancer": "Dark magic user. (placeholder)",
}

var _class_id: String = ""
var _appearance := {"body": 0, "hair": 0, "face": 0, "skin": 0}
var _busy: bool = false

var _columns: HBoxContainer
var _name: LineEdit
var _name_hint: Label
var _blurb: Label
var _value_labels := {}
var _create: Button
var _sign_out: Button
var _message: Label
var _all_buttons: Array[Button] = []


func _ready() -> void:
	theme = TSMTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


# ---------- UI ----------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = TSMTheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# The panel fills the screen height. Title and buttons stay fixed; only the
	# middle part scrolls, so "Create Character" is always reachable on phones.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	# On phones, lift the form above the on-screen keyboard.
	var avoider := KeyboardAvoider.new()
	avoider.content = margin
	add_child(avoider)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1200, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := Label.new()
	title.text = "CREATE YOUR CHARACTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TSMTheme.ACCENT)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_columns = HBoxContainer.new()
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 40)
	scroll.add_child(_columns)
	_columns.add_child(_build_class_column())
	_columns.add_child(_build_details_column())

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(0, 30)
	_message.add_theme_font_size_override("font_size", 20)
	root.add_child(_message)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	root.add_child(buttons)

	_sign_out = _make_button("Sign Out", 20)
	_sign_out.pressed.connect(_on_sign_out)
	buttons.add_child(_sign_out)

	_create = _make_button("Create Character", 28)
	_create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create.pressed.connect(_on_create)
	buttons.add_child(_create)


func _build_class_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "Class"
	heading.add_theme_color_override("font_color", TSMTheme.ACCENT)
	column.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)

	var group := ButtonGroup.new()
	for class_id in Session.CLASS_IDS:
		var button := _make_button(str(class_id).capitalize(), 22)
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 60)
		button.pressed.connect(_select_class.bind(str(class_id)))
		grid.add_child(button)
		if _class_id == "":
			button.button_pressed = true
			_class_id = str(class_id)

	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(0, 60)
	_blurb.add_theme_color_override("font_color", TSMTheme.MUTED)
	column.add_child(_blurb)
	_select_class(_class_id)
	return column


func _build_details_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)

	var name_heading := Label.new()
	name_heading.text = "Name"
	name_heading.add_theme_color_override("font_color", TSMTheme.ACCENT)
	column.add_child(name_heading)

	_name = LineEdit.new()
	_name.placeholder_text = "3-16 letters, numbers or _"
	_name.custom_minimum_size = Vector2(0, 52)
	_name.text_changed.connect(_on_name_changed)
	column.add_child(_name)

	_name_hint = Label.new()
	_name_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_hint.custom_minimum_size = Vector2(0, 44)
	_name_hint.add_theme_font_size_override("font_size", 17)
	column.add_child(_name_hint)
	_on_name_changed("")

	var look_heading := Label.new()
	look_heading.text = "Appearance"
	look_heading.add_theme_color_override("font_color", TSMTheme.ACCENT)
	column.add_child(look_heading)

	for key in ["body", "hair", "face", "skin"]:
		column.add_child(_build_appearance_row(key))

	var note := Label.new()
	note.text = "A 3D preview will appear here once the character models are in."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", TSMTheme.MUTED)
	column.add_child(note)
	return column


func _build_appearance_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = key.capitalize()
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var previous := _make_button("<", 22)
	previous.custom_minimum_size = Vector2(60, 52)
	previous.pressed.connect(_cycle.bind(key, -1))
	row.add_child(previous)

	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(110, 0)
	row.add_child(value)
	_value_labels[key] = value

	var next := _make_button(">", 22)
	next.custom_minimum_size = Vector2(60, 52)
	next.pressed.connect(_cycle.bind(key, 1))
	row.add_child(next)

	_update_value_label(key)
	return row


func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 60)
	button.add_theme_font_size_override("font_size", font_size)
	_all_buttons.append(button)
	return button


# ---------- Actions ----------

func _select_class(class_id: String) -> void:
	_class_id = class_id
	_blurb.text = str(CLASS_BLURBS.get(class_id, ""))


func _cycle(key: String, step: int) -> void:
	var count: int = APPEARANCE_COUNTS[key]
	_appearance[key] = (int(_appearance[key]) + step + count) % count
	_update_value_label(key)


func _update_value_label(key: String) -> void:
	var label: Label = _value_labels[key]
	label.text = "%d / %d" % [int(_appearance[key]) + 1, int(APPEARANCE_COUNTS[key])]


func _set_busy(busy: bool) -> void:
	_busy = busy
	for button in _all_buttons:
		button.disabled = busy
	_name.editable = not busy


func _show_error(text: String) -> void:
	_message.add_theme_color_override("font_color", TSMTheme.ERROR)
	_message.text = text


func _on_name_changed(text: String) -> void:
	if text == "":
		_set_name_hint("3-16 characters. Letters, numbers and underscores only. No spaces or special characters.",
				TSMTheme.MUTED, false)
		return
	var problem := Session.name_problem(text)
	if problem != "":
		_set_name_hint(problem, TSMTheme.ERROR, true)
	else:
		_set_name_hint("Name looks good (%d/%d)." % [text.length(), Session.NAME_MAX_LENGTH],
				TSMTheme.OK, false)


func _set_name_hint(text: String, color: Color, is_error: bool) -> void:
	_name_hint.text = text
	_name_hint.add_theme_color_override("font_color", color)
	if is_error:
		_name.add_theme_stylebox_override("normal", TSMTheme.error_box())
		_name.add_theme_stylebox_override("focus", TSMTheme.error_box())
	else:
		_name.remove_theme_stylebox_override("normal")
		_name.remove_theme_stylebox_override("focus")


func _on_create() -> void:
	if _busy:
		return
	var problem := Session.name_problem(_name.text)
	if problem != "":
		_on_name_changed(_name.text)
		_show_error(problem)
		return
	_set_busy(true)
	_message.add_theme_color_override("font_color", TSMTheme.MUTED)
	_message.text = "Creating your character..."

	var result: Dictionary = await Session.create_character(
			FlowRouter.CHARACTER_SLOT, _name.text, _class_id, _appearance.duplicate())
	if not result["ok"]:
		_set_busy(false)
		_show_error(str(result.get("message", "Could not create the character.")))
		return

	LoadingScreen.go(get_tree(), FlowRouter.WORLD_SCENE)


func _on_sign_out() -> void:
	FirebaseService.sign_out()
	FlowRouter.go_to_auth(get_tree())
