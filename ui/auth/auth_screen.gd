extends Control
## Login / registration screen. The UI is built in code.

enum Mode { SIGN_IN, REGISTER }

const PREFS_PATH := "user://prefs.cfg"

var _mode: Mode = Mode.SIGN_IN
var _busy: bool = false

var _center: CenterContainer
var _tab_sign_in: Button
var _tab_register: Button
var _email: LineEdit
var _password: LineEdit
var _confirm: LineEdit
var _show_password: CheckBox
var _submit: Button
var _forgot: Button
var _message: Label


func _ready() -> void:
	theme = TSMTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_email.text = _load_saved_email()
	_apply_mode()


# ---------- UI ----------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = TSMTheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_center = center

	# On phones, lift the form above the on-screen keyboard.
	var avoider := KeyboardAvoider.new()
	avoider.content = center
	add_child(avoider)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "THE SHADOW MOONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(title)

	var tagline := Label.new()
	tagline.text = "The moons have fallen, the darkness has awakened, a new legend will rise."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(540, 0)
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", TSMTheme.MUTED)
	box.add_child(tagline)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	_tab_sign_in = _make_tab("Sign In", group, Mode.SIGN_IN)
	_tab_register = _make_tab("Create Account", group, Mode.REGISTER)
	tabs.add_child(_tab_sign_in)
	tabs.add_child(_tab_register)
	_tab_sign_in.button_pressed = true

	_email = _make_line("Email", false)
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email.text_submitted.connect(_on_email_submitted)
	box.add_child(_email)

	_password = _make_line("Password (at least 6 characters)", true)
	_password.text_submitted.connect(_on_password_submitted)
	box.add_child(_password)

	_confirm = _make_line("Confirm password", true)
	_confirm.text_submitted.connect(_on_text_submitted)
	box.add_child(_confirm)

	_show_password = CheckBox.new()
	_show_password.text = "Show password"
	_show_password.toggled.connect(_on_show_password_toggled)
	box.add_child(_show_password)

	_submit = Button.new()
	_submit.custom_minimum_size = Vector2(0, 60)
	_submit.add_theme_font_size_override("font_size", 26)
	_submit.pressed.connect(_on_submit)
	box.add_child(_submit)

	_forgot = Button.new()
	_forgot.text = "Forgot password?"
	_forgot.flat = true
	_forgot.add_theme_font_size_override("font_size", 18)
	_forgot.pressed.connect(_on_forgot)
	box.add_child(_forgot)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(540, 44)
	_message.add_theme_font_size_override("font_size", 20)
	box.add_child(_message)


func _make_tab(text: String, group: ButtonGroup, mode: Mode) -> Button:
	var tab := Button.new()
	tab.text = text
	tab.toggle_mode = true
	tab.button_group = group
	tab.custom_minimum_size = Vector2(0, 52)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.pressed.connect(_set_mode.bind(mode))
	return tab


func _make_line(placeholder: String, secret: bool) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	line.secret = secret
	line.custom_minimum_size = Vector2(0, 56)
	return line


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_apply_mode()


func _apply_mode() -> void:
	var registering := _mode == Mode.REGISTER
	_confirm.visible = registering
	_forgot.visible = not registering
	_submit.text = "Create Account" if registering else "Sign In"
	_message.text = ""


func _set_busy(busy: bool) -> void:
	_busy = busy
	_submit.disabled = busy
	_forgot.disabled = busy
	_tab_sign_in.disabled = busy
	_tab_register.disabled = busy
	_email.editable = not busy
	_password.editable = not busy
	_confirm.editable = not busy


func _show_error(text: String) -> void:
	_message.add_theme_color_override("font_color", TSMTheme.ERROR)
	_message.text = text


func _show_info(text: String) -> void:
	_message.add_theme_color_override("font_color", TSMTheme.MUTED)
	_message.text = text


# ---------- Actions ----------

func _on_show_password_toggled(shown: bool) -> void:
	_password.secret = not shown
	_confirm.secret = not shown


func _on_email_submitted(_text: String) -> void:
	_password.grab_focus()


func _on_password_submitted(_text: String) -> void:
	if _mode == Mode.REGISTER:
		_confirm.grab_focus()
	else:
		_on_submit()


func _on_text_submitted(_text: String) -> void:
	_on_submit()


func _on_forgot() -> void:
	if _busy:
		return
	var email := _email.text.strip_edges()
	if not email.contains("@") or not email.contains("."):
		_show_error("Type your email address above first.")
		return

	_set_busy(true)
	_show_info("Sending...")
	var result: Dictionary = await FirebaseService.send_password_reset(email)
	_set_busy(false)

	# The same answer whether or not the account exists, so this screen
	# can't be used to find out which emails are registered.
	if result["ok"] or result.get("error", "") == "EMAIL_NOT_FOUND":
		_show_info("If an account exists for that email, a reset link has been sent. Check your inbox and spam folder.")
	else:
		_show_error(str(result.get("message", "Could not send the email.")))


func _on_submit() -> void:
	if _busy:
		return

	var email := _email.text.strip_edges()
	var password := _password.text
	if not email.contains("@") or not email.contains("."):
		_show_error("Enter a valid email address.")
		return
	if password.length() < 6:
		_show_error("Password must be at least 6 characters.")
		return
	if _mode == Mode.REGISTER and password != _confirm.text:
		_show_error("The two passwords don't match.")
		return

	_set_busy(true)
	_show_info("Contacting the server...")

	var result: Dictionary
	if _mode == Mode.REGISTER:
		result = await FirebaseService.sign_up(email, password)
	else:
		result = await FirebaseService.sign_in(email, password)

	if not result["ok"]:
		_set_busy(false)
		_show_error(str(result.get("message", "Something went wrong.")))
		return

	_save_email(email)
	_show_info("Loading your account...")
	var flow: Dictionary = await FlowRouter.continue_after_sign_in(get_tree())
	if not flow["ok"]:
		_set_busy(false)
		_show_error(str(flow.get("message", "Could not load your account.")))
	# On success the scene changes, so nothing else happens here.


# ---------- Remembered email ----------

func _load_saved_email() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return ""
	return str(cfg.get_value("login", "email", ""))


func _save_email(email: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)    # keep other settings if the file exists
	cfg.set_value("login", "email", email)
	cfg.save(PREFS_PATH)
