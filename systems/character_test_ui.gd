extends Control
## Temporary M2.3 test screen: sign in, then create / load / save a character.
## The whole UI is built in code, so the scene only needs a Control root.

var _email: LineEdit
var _password: LineEdit
var _name: LineEdit
var _class: OptionButton
var _output: TextEdit
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(700, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Character Test (M2.3)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)

	_email = _add_line_edit(box, "Email", false)
	_password = _add_line_edit(box, "Password", true)
	_add_button_row(box, [["Sign In", _on_sign_in], ["Sign Out", _on_sign_out]])

	_name = _add_line_edit(box, "Character name (3-16 letters, numbers, _)", false)
	_class = OptionButton.new()
	_class.custom_minimum_size = Vector2(0, 52)
	_class.add_theme_font_size_override("font_size", 20)
	for class_id in Session.CLASS_IDS:
		_class.add_item(str(class_id).capitalize())
	box.add_child(_class)

	_add_button_row(box, [
		["Create", _on_create],
		["Load", _on_load],
		["Level +1 (save)", _on_level_up],
	])

	_output = TextEdit.new()
	_output.editable = false
	_output.custom_minimum_size = Vector2(0, 330)
	_output.add_theme_font_size_override("font_size", 18)
	box.add_child(_output)

	_log({"info": "Configured: %s" % str(FirebaseService.is_configured())})
	_try_restore()


func _add_line_edit(parent: Control, placeholder: String, secret: bool) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	line.secret = secret
	line.custom_minimum_size = Vector2(0, 52)
	line.add_theme_font_size_override("font_size", 20)
	parent.add_child(line)
	return line


func _add_button_row(parent: Control, entries: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for entry in entries:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(entry[1])
		row.add_child(button)
		_buttons.append(button)


func _set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy


func _log(result: Dictionary) -> void:
	_output.text = JSON.stringify({
		"result": result,
		"signed_in": FirebaseService.is_signed_in(),
		"uid": FirebaseService.uid,
		"character": Session.character,
	}, "  ")
	print("[CharacterTestUI] ", result)


# After any successful sign-in: make sure the profile exists, then load slot 1.
func _after_sign_in() -> Dictionary:
	var profile: Dictionary = await Session.ensure_profile()
	if not profile["ok"]:
		return profile
	return await Session.load_character(1)


func _try_restore() -> void:
	_set_busy(true)
	var result: Dictionary = await FirebaseService.try_restore_session()
	if result["ok"]:
		result = await _after_sign_in()
		result["info"] = "Session restored automatically"
	_set_busy(false)
	_log(result)


func _on_sign_in() -> void:
	_set_busy(true)
	var result: Dictionary = await FirebaseService.sign_in(_email.text, _password.text)
	if result["ok"]:
		result = await _after_sign_in()
	_set_busy(false)
	_log(result)


func _on_sign_out() -> void:
	FirebaseService.sign_out()
	_log({"info": "Signed out"})


func _on_create() -> void:
	_set_busy(true)
	var class_id: String = Session.CLASS_IDS[_class.selected]
	var appearance := {"body": 0, "hair": 0, "face": 0, "skin": 0}
	var result: Dictionary = await Session.create_character(1, _name.text, class_id, appearance)
	_set_busy(false)
	_log(result)


func _on_load() -> void:
	_set_busy(true)
	var result: Dictionary = await Session.load_character(1)
	_set_busy(false)
	_log(result)


func _on_level_up() -> void:
	if not Session.has_character():
		_log({"ok": false, "message": "No character loaded. Create or Load one first."})
		return
	_set_busy(true)
	var new_level := int(Session.character.get("level", 1)) + 1
	var result: Dictionary = await Session.save_fields({"level": new_level})
	_set_busy(false)
	_log(result)
