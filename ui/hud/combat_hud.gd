class_name CombatHud
extends Control
## Health, mana and stamina bars for the player, a target frame (name, health,
## status effects and a damage-per-second meter for the training dummy), and
## short messages like "No target in range". It only shows information.
## Call setup(player) once.

var _player: PlayerController
var _target: Node3D

var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _sp_bar: ProgressBar
var _hp_text: Label
var _mp_text: Label
var _sp_text: Label

var _target_panel: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _target_text: Label
var _target_status: Label
var _target_dps: Label

var _message: Label
var _message_time: float = 0.0
var _refresh_time: float = 0.0


func setup(player: PlayerController) -> void:
	_player = player
	theme = TSMTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_player_bars()
	_build_target_frame()
	_build_message()

	player.combatant.changed.connect(_refresh_player)
	player.target_changed.connect(_on_target_changed)
	player.attack_failed.connect(show_message)
	_refresh_player()
	_refresh_target()


func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message_time = 1.4


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)
	_refresh_time += delta
	if _refresh_time >= 0.1:
		_refresh_time = 0.0
		_refresh_target()


# ---------- building ----------

func _build_player_bars() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 64)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var hp := _bar_row(box, "HP", Color("ff0000"))
	_hp_bar = hp[0]
	_hp_text = hp[1]
	var mp := _bar_row(box, "MP", Color("0000ff"))
	_mp_bar = mp[0]
	_mp_text = mp[1]
	var sp := _bar_row(box, "SP", Color("00ff00"))
	_sp_bar = sp[0]
	_sp_text = sp[1]


func _bar_row(parent: Control, label_text: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(36, 0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", TSMTheme.MUTED)
	row.add_child(label)

	var bar := _make_bar(color, Vector2(260, 20))
	row.add_child(bar)

	var value := Label.new()
	value.add_theme_font_size_override("font_size", 16)
	row.add_child(value)
	return [bar, value]


func _make_bar(color: Color, min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0001
	bar.custom_minimum_size = min_size
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0d0718")
	background.border_color = TSMTheme.BORDER
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	return bar


func _build_target_frame() -> void:
	_target_panel = PanelContainer.new()
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.offset_left = -240
	_target_panel.offset_right = 240
	_target_panel.offset_top = 14
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TSMTheme.PANEL, 0.9)
	style.border_color = TSMTheme.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_target_panel.add_theme_stylebox_override("panel", style)
	_target_panel.visible = false
	add_child(_target_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_target_panel.add_child(box)

	_target_name = Label.new()
	_target_name.add_theme_font_size_override("font_size", 20)
	_target_name.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(_target_name)

	_target_bar = _make_bar(Color("ff0000"), Vector2(0, 20))
	box.add_child(_target_bar)

	_target_text = Label.new()
	_target_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_target_text)

	_target_status = Label.new()
	_target_status.add_theme_font_size_override("font_size", 16)
	_target_status.add_theme_color_override("font_color", Color("FFD700"))
	box.add_child(_target_status)

	_target_dps = Label.new()
	_target_dps.add_theme_font_size_override("font_size", 16)
	_target_dps.add_theme_color_override("font_color", Color("8fd0ff"))
	box.add_child(_target_dps)


func _build_message() -> void:
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_message.offset_left = -300
	_message.offset_right = 300
	_message.offset_top = -190
	_message.offset_bottom = -150
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.add_theme_color_override("font_color", TSMTheme.ERROR)
	_message.modulate.a = 0.0
	add_child(_message)


# ---------- updating ----------

func _on_target_changed(target: Node3D) -> void:
	_target = target
	_refresh_target()


func _refresh_player() -> void:
	var fighter := _player.combatant
	_set_bar(_hp_bar, _hp_text, fighter.hp, fighter.max_health())
	_set_bar(_mp_bar, _mp_text, fighter.mp, fighter.max_mana())
	_set_bar(_sp_bar, _sp_text, fighter.sp, fighter.max_stamina())


func _set_bar(bar: ProgressBar, text: Label, value: int, maximum: int) -> void:
	bar.value = float(value) / maxf(1.0, float(maximum))
	text.text = "%d / %d" % [value, maximum]


func _refresh_target() -> void:
	if _target_panel == null:
		return
	if not Targeting.is_valid_target(_target):
		_target_panel.visible = false
		return
	var fighter: Combatant = _target.get("combatant")
	_target_panel.visible = true
	_target_name.text = "%s   Lv %d" % [fighter.display_name, fighter.level]
	_target_bar.value = float(fighter.hp) / maxf(1.0, float(fighter.max_health()))
	_target_text.text = "HP %d / %d" % [fighter.hp, fighter.max_health()]

	var effects: Array = []
	for effect_id in fighter.status.active_ids():
		var count := fighter.status.stacks(effect_id)
		var effect_name := str(DataRegistry.get_status_effect(effect_id).get("name", effect_id))
		effects.append("%s x%d" % [effect_name, count] if count > 1 else effect_name)
	_target_status.text = ", ".join(effects)
	_target_status.visible = not effects.is_empty()

	var meter: Variant = _target.get("dps_meter")
	_target_dps.visible = meter is DpsMeter
	if meter is DpsMeter:
		var dps := meter as DpsMeter
		_target_dps.text = "DPS (5s): %d    Total: %d    Hits: %d    Crits: %d    Misses: %d" % [
				roundi(dps.dps()), dps.total, dps.hits, dps.crits, dps.misses]
