class_name CombatHud
extends Control
## The in-game HUD. Top left: name, class and level, health / mana / stamina bars,
## the EXP bar (with 4 decimals), gold, status effects on you, and the reward feed.
## Top centre: the target frame (health, effects, DPS for the dummy). Top right:
## Bag and Char buttons that open the windows. Messages, the LEVEL UP banner and
## the death panel sit in the middle. It only shows information and asks for things.
## Call setup(player) once.

signal sign_out_requested

var inventory_window: InventoryWindow
var character_window: CharacterWindow

var _player: PlayerController
var _controls: TouchControls
var _target: Node3D

var _name_label: Label
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _sp_bar: ProgressBar
var _hp_text: Label
var _mp_text: Label
var _sp_text: Label
var _exp_bar: ProgressBar
var _exp_text: Label
var _gold_label: Label
var _buff_box: HBoxContainer
var _buff_signature: String = ""
var _feed: VBoxContainer

var _target_panel: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _target_text: Label
var _target_status: Label
var _target_dps: Label

var _banner: Label
var _death_panel: PanelContainer
var _message: Label
var _message_time: float = 0.0
var _refresh_time: float = 0.0


func setup(player: PlayerController) -> void:
	_player = player
	_controls = player.controls
	theme = TSMTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_left_column()
	_build_menu_buttons()
	_build_target_frame()
	_build_message()
	_build_banner()
	_build_death_panel()
	_build_windows()

	Session.reward_granted.connect(_on_reward)
	Session.character_changed.connect(_refresh_player)
	player.died.connect(func() -> void: _death_panel.visible = true)
	player.revived.connect(func() -> void: _death_panel.visible = false)
	player.combatant.changed.connect(_refresh_player)
	player.target_changed.connect(_on_target_changed)
	player.attack_failed.connect(show_message)
	_refresh_player()
	_refresh_target()


func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message_time = 1.4


func is_window_open() -> bool:
	return inventory_window.visible or character_window.visible


func open_inventory() -> void:
	_open(inventory_window, character_window)


func open_character() -> void:
	_open(character_window, inventory_window)


func close_windows() -> void:
	inventory_window.close()
	character_window.close()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)
	_refresh_time += delta
	if _refresh_time >= 0.1:
		_refresh_time = 0.0
		_refresh_target()
		_refresh_buffs()


# ---------- building ----------

func _panel_style(margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TSMTheme.PANEL, 0.88)
	style.border_color = TSMTheme.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(margin)
	return style


func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(16, 12)
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style())
	column.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	frame.add_child(box)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(_name_label)

	var hp := _bar_row(box, "HP", Color("c0392b"))
	_hp_bar = hp[0]
	_hp_text = hp[1]
	var mp := _bar_row(box, "MP", Color("2f7fd1"))
	_mp_bar = mp[0]
	_mp_text = mp[1]
	var sp := _bar_row(box, "SP", Color("3aa655"))
	_sp_bar = sp[0]
	_sp_text = sp[1]

	_exp_bar = _make_bar(Color("8fd0ff"), Vector2(300, 12))
	box.add_child(_exp_bar)
	_exp_text = Label.new()
	_exp_text.add_theme_font_size_override("font_size", 15)
	_exp_text.add_theme_color_override("font_color", TSMTheme.MUTED)
	box.add_child(_exp_text)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(_gold_label)

	_buff_box = HBoxContainer.new()
	_buff_box.add_theme_constant_override("separation", 4)
	_buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_buff_box)

	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 2)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_feed)


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

	var bar := _make_bar(color, Vector2(220, 18))
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
	bar.step = 0.00001
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


func _build_menu_buttons() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -300
	row.offset_right = -16
	row.offset_top = 12
	row.offset_bottom = 84
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for entry in [["Bag", open_inventory], ["Char", open_character]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(130, 72)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(entry[1])
		row.add_child(button)


func _build_target_frame() -> void:
	_target_panel = PanelContainer.new()
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.offset_left = -240
	_target_panel.offset_right = 240
	_target_panel.offset_top = 14
	_target_panel.add_theme_stylebox_override("panel", _panel_style())
	_target_panel.visible = false
	add_child(_target_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_target_panel.add_child(box)

	_target_name = Label.new()
	_target_name.add_theme_font_size_override("font_size", 20)
	_target_name.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(_target_name)

	_target_bar = _make_bar(Color("c0392b"), Vector2(0, 20))
	box.add_child(_target_bar)

	_target_text = Label.new()
	_target_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_target_text)

	_target_status = Label.new()
	_target_status.add_theme_font_size_override("font_size", 16)
	_target_status.add_theme_color_override("font_color", Color("ffb36b"))
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
	_message.offset_top = -200
	_message.offset_bottom = -160
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.add_theme_color_override("font_color", TSMTheme.ERROR)
	_message.modulate.a = 0.0
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message)


func _build_banner() -> void:
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -300
	_banner.offset_right = 300
	_banner.offset_top = 220
	_banner.offset_bottom = 280
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_color_override("font_color", TSMTheme.ACCENT)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)


func _build_death_panel() -> void:
	_death_panel = PanelContainer.new()
	_death_panel.set_anchors_preset(Control.PRESET_CENTER)
	_death_panel.offset_left = -220
	_death_panel.offset_right = 220
	_death_panel.offset_top = -120
	_death_panel.offset_bottom = 120
	_death_panel.visible = false
	add_child(_death_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_death_panel.add_child(box)

	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", TSMTheme.ERROR)
	box.add_child(title)

	var revive := Button.new()
	revive.text = "Revive"
	revive.custom_minimum_size = Vector2(0, 80)
	revive.add_theme_font_size_override("font_size", 30)
	revive.pressed.connect(func() -> void: _player.revive())
	box.add_child(revive)


func _build_windows() -> void:
	inventory_window = InventoryWindow.new()
	add_child(inventory_window)
	inventory_window.setup(_player)
	inventory_window.closed.connect(_on_window_closed)

	character_window = CharacterWindow.new()
	add_child(character_window)
	character_window.setup()
	character_window.closed.connect(_on_window_closed)
	character_window.sign_out_requested.connect(func() -> void: sign_out_requested.emit())


# ---------- windows ----------

func _open(window: GameWindow, other: GameWindow) -> void:
	other.close()
	window.open()
	if _controls != null:
		_controls.enabled = false       # taps on a window must not move the character


func _on_window_closed() -> void:
	if not is_window_open() and _controls != null:
		_controls.enabled = true


# ---------- rewards ----------

## One line in the reward list at the top left. It fades away on its own.
func add_feed(text: String, color: Color) -> void:
	var line := Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", 18)
	line.add_theme_color_override("font_color", color)
	_feed.add_child(line)
	while _feed.get_child_count() > 8:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tween := line.create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(line, "modulate:a", 0.0, 0.6)
	tween.tween_callback(line.queue_free)


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tween := _banner.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


func _on_reward(summary: Dictionary) -> void:
	if int(summary.get("exp", 0)) > 0:
		add_feed("+%d EXP" % int(summary["exp"]), Color("8fd0ff"))
	if int(summary.get("gold", 0)) > 0:
		add_feed("+%d gold" % int(summary["gold"]), TSMTheme.ACCENT)
	for entry in summary.get("items", []):
		var item_id := str(entry["item_id"])
		add_feed("+ %s" % ItemDB.display_name(item_id), TSMTheme.rarity_color(ItemDB.rarity(item_id)))
	if int(summary.get("levels_gained", 0)) > 0:
		show_banner("LEVEL UP!  Lv %d" % int(summary.get("level", 1)))


# ---------- updating ----------

func _on_target_changed(target: Node3D) -> void:
	_target = target
	_refresh_target()


func _refresh_player() -> void:
	if _player == null or not Session.has_character():
		return
	var fighter := _player.combatant
	var c := Session.character
	_name_label.text = "%s   %s  Lv %d" % [str(c.get("name", "?")),
			str(c.get("class_id", "?")).capitalize(), int(c.get("level", 1))]
	_set_bar(_hp_bar, _hp_text, fighter.hp, fighter.max_health())
	_set_bar(_mp_bar, _mp_text, fighter.mp, fighter.max_mana())
	_set_bar(_sp_bar, _sp_text, fighter.sp, fighter.max_stamina())
	var level := int(c.get("level", 1))
	_exp_bar.value = StatDisplay.exp_fraction(level, int(c.get("exp", 0)), int(c.get("rebirth", 0)))
	_exp_text.text = StatDisplay.exp_text(level, int(c.get("exp", 0)), int(c.get("rebirth", 0)))
	_gold_label.text = "Gold  %s" % StatDisplay.format_number(int(c.get("gold", 0)))


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


## Status effects on the player: a small chip each, with the time left.
func _refresh_buffs() -> void:
	if _player == null or _player.combatant == null:
		return
	var status := _player.combatant.status
	var ids := status.active_ids()
	var signature: Array = []
	for effect_id in ids:
		signature.append("%s:%d" % [effect_id, status.stacks(effect_id)])
	var key := ",".join(signature)

	if key != _buff_signature:
		_buff_signature = key
		GameWindow.clear_children(_buff_box)
		for effect_id in ids:
			_buff_box.add_child(_make_buff_chip(str(effect_id)))
	for chip in _buff_box.get_children():
		var effect_id := str(chip.name)
		var label := chip.get_child(0) as Label
		var seconds := ceili(status.remaining(effect_id))
		var count := status.stacks(effect_id)
		var effect_name := str(DataRegistry.get_status_effect(effect_id).get("name", effect_id))
		label.text = "%s%s %ds" % [effect_name, (" x%d" % count) if count > 1 else "", seconds]


func _make_buff_chip(effect_id: String) -> Control:
	var kind := str(DataRegistry.get_status_effect(effect_id).get("kind", "debuff"))
	var color := Color("ffb36b")
	if kind == "buff" or kind == "hot":
		color = Color("7be07b")
	elif kind == "cc":
		color = Color("7fb4ff")
	var chip := PanelContainer.new()
	chip.name = effect_id
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TSMTheme.PANEL, 0.9)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	chip.add_child(label)
	return chip
