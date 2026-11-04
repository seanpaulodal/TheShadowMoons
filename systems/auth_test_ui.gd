extends Control
## Temporary M2.1 / M2.2 test screen. The whole UI is built in code,
## so the scene only needs a Control root.

var _email: LineEdit
var _password: LineEdit
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "Auth Test (M2.2)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	_email = LineEdit.new()
	_email.placeholder_text = "Email"
	_email.custom_minimum_size = Vector2(0, 56)
	_email.add_theme_font_size_override("font_size", 22)
	box.add_child(_email)

	_password = LineEdit.new()
	_password.placeholder_text = "Password (at least 6 characters)"
	_password.secret = true
	_password.custom_minimum_size = Vector2(0, 56)
	_password.add_theme_font_size_override("font_size", 22)
	box.add_child(_password)

	_add_button(box, "Sign Up", _on_sign_up)
	_add_button(box, "Sign In", _on_sign_in)
	_add_button(box, "Sign Out", _on_sign_out)

	_status = Label.new()
	_status.text = "Configured: %s" % str(FirebaseService.is_configured())
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 110)
	_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_status)

	# M2.2: try to continue the previous session automatically.
	_try_restore()


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons.append(button)


func _set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy
	if busy:
		_status.text = "Working..."


func _show_result(result: Dictionary) -> void:
	_set_busy(false)
	if result["ok"]:
		_status.text = "Success. Signed in as %s\nuid: %s" % [
				FirebaseService.user_email, FirebaseService.uid]
	else:
		_status.text = "Failed: %s" % result.get("message", result.get("error", "unknown"))
	print("[AuthTestUI] ", result)


func _try_restore() -> void:
	_set_busy(true)
	var result: Dictionary = await FirebaseService.try_restore_session()
	_set_busy(false)
	if result["ok"]:
		_status.text = "Session restored automatically.\nSigned in as %s\nuid: %s" % [
				FirebaseService.user_email, FirebaseService.uid]
	else:
		_status.text = "No session restored: %s" % result.get("message", "")
	print("[AuthTestUI] restore -> ", result)


func _on_sign_up() -> void:
	_set_busy(true)
	var result: Dictionary = await FirebaseService.sign_up(_email.text, _password.text)
	_show_result(result)


func _on_sign_in() -> void:
	_set_busy(true)
	var result: Dictionary = await FirebaseService.sign_in(_email.text, _password.text)
	_show_result(result)


func _on_sign_out() -> void:
	FirebaseService.sign_out()
	_status.text = "Signed out. The saved session was deleted."
