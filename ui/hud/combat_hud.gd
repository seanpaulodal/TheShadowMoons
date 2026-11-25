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
var shop_window: ShopWindow
var map_window: WaypointWindow
var skill_window: SkillWindow
var minimap: Minimap
## How long the screen fades when teleporting (seconds each way).
var fade_seconds: float = 0.35

signal teleported(waypoint_id: String)

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
var _quick_buttons: Dictionary = {}     # resource -> {"button", "icon", "count", "shade", "time"}
var _interact_button: Button
var _interact_npc: ShopNpc
var _interact_waypoint: Waypoint
var _time_label: Label
var _fade: ColorRect
var _fade_label: Label
var _teleporting: bool = false
var _clock_timer: float = 0.0
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
	_build_quick_slots()
	_build_interact_button()
	_build_minimap()
	_build_windows()
	_build_fade()

	Session.reward_granted.connect(_on_reward)
	Session.character_changed.connect(_refresh_player)
	player.died.connect(func() -> void:
		close_windows()
		_death_panel.visible = true)
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
	return inventory_window.visible or character_window.visible or shop_window.visible \
			or map_window.visible or skill_window.visible or minimap.expanded


func open_inventory() -> void:
	_open(inventory_window)


func open_character() -> void:
	_open(character_window)


func open_map() -> void:
	_open(map_window)


func open_skills() -> void:
	_open(skill_window)


## Opens a shop window (see TSM_Shop_Rules.json for the ids).
func open_shop(shop_id: String) -> void:
	minimap.collapse()
	_close_others(shop_window)
	shop_window.open_shop(shop_id)
	_refresh_interact()
	if _controls != null:
		_controls.enabled = false


func close_windows() -> void:
	inventory_window.close()
	character_window.close()
	shop_window.close()
	map_window.close()
	skill_window.close()
	minimap.collapse()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not is_window_open():
		_on_interact()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)
	_refresh_time += delta
	if _refresh_time >= 0.1:
		_refresh_time = 0.0
		_refresh_target()
		_refresh_buffs()
		_refresh_quick_slots()
		_refresh_interact()
		_clock_timer += 0.1
		if _clock_timer >= 1.0:
			_clock_timer = 0.0
			_refresh_clock()


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
	row.offset_left = -576
	row.offset_right = -16
	row.offset_top = 12
	row.offset_bottom = 84
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for entry in [["Bag", open_inventory], ["Char", open_character], ["Skills", open_skills], ["Map", open_map]]:
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

	shop_window = ShopWindow.new()
	add_child(shop_window)
	shop_window.setup()
	shop_window.closed.connect(_on_window_closed)

	skill_window = SkillWindow.new()
	add_child(skill_window)
	skill_window.setup()
	skill_window.closed.connect(_on_window_closed)

	map_window = WaypointWindow.new()
	add_child(map_window)
	map_window.setup(_player, str(Session.character.get("current_map", "map_1")))
	map_window.closed.connect(_on_window_closed)
	map_window.teleport_requested.connect(func(waypoint_id: String) -> void:
		var result := teleport_to(waypoint_id)
		if result["ok"]:
			map_window.show_message("", false)
		else:
			map_window.show_message(str(result["message"]), true))


func _build_quick_slots() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.offset_right = -264
	row.offset_left = -264 - 3 * 106
	row.offset_bottom = -70
	row.offset_top = -166
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var tags := {"health": "HP", "mana": "MP", "stamina": "SP"}
	for resource in DataRegistry.get_config("consumable_rules").get("quick_slots", []):
		var button := Button.new()
		button.custom_minimum_size = Vector2(96, 96)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, GameWindow.slot_style(Color("5b2a8c"), false))
		button.pressed.connect(_on_quick_slot.bind(str(resource)))
		row.add_child(button)

		var tag := Label.new()
		tag.text = str(tags.get(resource, ""))
		tag.position = Vector2(8, 2)
		tag.add_theme_font_size_override("font_size", 16)
		tag.add_theme_color_override("font_color", TSMTheme.MUTED)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(tag)

		var icon := Label.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 30)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)

		var count := Label.new()
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
		count.add_theme_font_size_override("font_size", 20)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count)

		# Darkens from the top down while the potion cools down.
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.62)
		shade.anchor_left = 0.0
		shade.anchor_right = 1.0
		shade.anchor_bottom = 1.0
		shade.anchor_top = 1.0
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(shade)

		var time := Label.new()
		time.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		time.add_theme_font_size_override("font_size", 28)
		time.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(time)

		_quick_buttons[resource] = {"button": button, "icon": icon, "count": count, "shade": shade, "time": time}


func _build_interact_button() -> void:
	_interact_button = Button.new()
	_interact_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_button.offset_left = -170
	_interact_button.offset_right = 170
	_interact_button.offset_top = -270
	_interact_button.offset_bottom = -180
	_interact_button.add_theme_font_size_override("font_size", 28)
	_interact_button.visible = false
	_interact_button.pressed.connect(_on_interact)
	add_child(_interact_button)


func _on_quick_slot(resource: String) -> void:
	var result := _player.use_quick_slot(resource)
	if not result["ok"]:
		show_message(str(result.get("message", "")))


func _refresh_quick_slots() -> void:
	if _player == null or not Session.has_character():
		return
	var slots: Dictionary = Session.character.get("settings", {}).get("quick_slots", {})
	for resource in _quick_buttons:
		var parts: Dictionary = _quick_buttons[resource]
		var item_id := str(slots.get(resource, ""))
		var owned := Inventory.count(Session.character.get("inventory", []), item_id) if item_id != "" else 0
		(parts["icon"] as Label).text = GameWindow.initials(item_id) if item_id != "" else "+"
		(parts["icon"] as Label).add_theme_color_override("font_color",
				TSMTheme.rarity_color(ItemDB.rarity(item_id)) if item_id != "" else Color("5d5470"))
		(parts["count"] as Label).text = "x%d" % owned if item_id != "" else ""
		(parts["button"] as Button).modulate.a = 1.0 if owned > 0 else 0.5

		var fraction := _player.potion_cooldowns.fraction(item_id) if item_id != "" else 0.0
		var shade := parts["shade"] as ColorRect
		shade.anchor_top = 1.0 - fraction
		shade.offset_top = 0.0
		shade.offset_bottom = 0.0
		var seconds := ceili(_player.potion_cooldowns.remaining(item_id)) if item_id != "" else 0
		(parts["time"] as Label).text = str(seconds) if seconds > 0 else ""


## Shows the Talk / Activate button while the player stands near a shopkeeper or
## a waypoint (whichever is closer).
func _refresh_interact() -> void:
	if _player == null or _interact_button == null:
		return
	_interact_npc = null
	_interact_waypoint = null
	if not is_window_open() and not _player.is_dead() and not _teleporting:
		var shop_radius := float(DataRegistry.get_config("shop_rules").get("interaction_radius", 3.5))
		var waypoint_radius := float(MapData.get_map(str(Session.character.get("current_map", "map_1"))).get("waypoint_radius", 3.2))
		var npc := ShopNpc.nearest(_player, shop_radius)
		var waypoint := Waypoint.nearest(_player, waypoint_radius)
		if npc != null and (waypoint == null or Vector2(_player.global_position.x - npc.global_position.x, _player.global_position.z - npc.global_position.z).length() <= waypoint.ground_distance(_player.global_position)):
			_interact_npc = npc
		else:
			_interact_waypoint = waypoint
	_interact_button.visible = _interact_npc != null or _interact_waypoint != null
	if _interact_npc != null:
		_interact_button.text = "Talk: %s" % _interact_npc.display_name
	elif _interact_waypoint != null:
		_interact_button.text = ("Waypoint: %s" if _interact_waypoint.unlocked else "Activate: %s") % _interact_waypoint.display_name


func _on_interact() -> void:
	if _interact_npc != null:
		open_shop(_interact_npc.shop_id)
	elif _interact_waypoint != null:
		if _interact_waypoint.unlocked:
			open_map()
		else:
			activate_waypoint(_interact_waypoint)


## Turns a waypoint blue if you are close enough and the area is clear of enemies.
func activate_waypoint(waypoint: Waypoint) -> Dictionary:
	var map := MapData.get_map(str(Session.character.get("current_map", "map_1")))
	var error := WaypointRules.activation_error(waypoint.unlocked,
			waypoint.ground_distance(_player.global_position),
			waypoint.enemies_near(float(map.get("waypoint_clear_radius", 16.0))),
			float(map.get("waypoint_radius", 3.2)))
	if error != "":
		show_message(WaypointRules.message(error))
		return {"ok": false, "error": error}
	Session.unlock_waypoint(waypoint.waypoint_id)
	show_banner("WAYPOINT ACTIVATED")
	add_feed("Waypoint: %s" % waypoint.display_name, Color("4aa8ff"))
	_refresh_interact()
	return {"ok": true}


## Teleports to an active waypoint: the screen fades out, you are moved, it fades in.
## Returns {"ok": true} (the fade then runs by itself) or a failure with a message.
func teleport_to(waypoint_id: String) -> Dictionary:
	if _teleporting:
		return {"ok": false, "error": "BUSY", "message": "Already teleporting."}
	var map_id := str(Session.character.get("current_map", "map_1"))
	var error := WaypointRules.teleport_error(Session.character, waypoint_id, _player.is_dead(),
			_player.seconds_since_combat(), float(MapData.get_map(map_id).get("teleport_combat_delay", 5.0)))
	if error != "":
		return {"ok": false, "error": error, "message": WaypointRules.message(error)}
	_run_teleport(waypoint_id, map_id)
	return {"ok": true}


func _run_teleport(waypoint_id: String, map_id: String) -> void:
	_teleporting = true
	close_windows()
	if _controls != null:
		_controls.enabled = false
	var entry := MapData.waypoint(map_id, waypoint_id)
	var at := MapData.position_of(entry)
	_fade_label.text = "Teleporting to %s..." % str(entry.get("name", ""))
	_fade.visible = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP

	var fade_out := create_tween()
	fade_out.tween_property(_fade, "modulate:a", 1.0, fade_seconds)
	await fade_out.finished
	_player.teleport_to(Vector3(at.x, 0.0, at.y + 3.0))       # beside the obelisk, not inside it
	await get_tree().create_timer(fade_seconds * 0.7).timeout
	var fade_in := create_tween()
	fade_in.tween_property(_fade, "modulate:a", 0.0, fade_seconds)
	await fade_in.finished

	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _controls != null and not is_window_open():
		_controls.enabled = true
	_teleporting = false
	teleported.emit(waypoint_id)


func is_teleporting() -> bool:
	return _teleporting


func _build_minimap() -> void:
	minimap = Minimap.new()
	add_child(minimap)
	minimap.setup(_player, str(Session.character.get("current_map", "map_1")))
	minimap.toggled.connect(func(expanded: bool) -> void:
		if expanded:
			_close_others(null)
			if _controls != null:
				_controls.enabled = false
		else:
			_on_window_closed())

	_time_label = Label.new()
	_time_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_time_label.offset_left = -(Minimap.COMPACT_SIZE + 16.0)
	_time_label.offset_right = -16.0
	_time_label.offset_top = 96.0 + Minimap.COMPACT_SIZE + 4.0
	_time_label.offset_bottom = 96.0 + Minimap.COMPACT_SIZE + 34.0
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 18)
	_time_label.add_theme_color_override("font_color", TSMTheme.MUTED)
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_label)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade_label = Label.new()
	_fade_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.add_theme_font_size_override("font_size", 40)
	_fade_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	_fade.add_child(_fade_label)


## "Day  14:35" from the sky, updated about once a second.
func _refresh_clock() -> void:
	var sky := get_tree().get_first_node_in_group("day_night") as DayNight
	if sky == null:
		_time_label.text = ""
		return
	var hour := sky.current_hour()
	_time_label.text = "%s  %s" % [DayNightRules.period_name(hour), DayNightRules.format_hour(hour)]


# ---------- windows ----------

func _open(window: GameWindow) -> void:
	minimap.collapse()
	_close_others(window)
	window.open()
	_refresh_interact()
	if _controls != null:
		_controls.enabled = false       # taps on a window must not move the character


func _close_others(keep: GameWindow) -> void:
	for window in [inventory_window, character_window, shop_window, map_window, skill_window]:
		if window != keep:
			window.close()


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


## Status effects on the player: a small chip each, with the time left. An
## active elixir shows as a gold chip at the end.
func _refresh_buffs() -> void:
	if _player == null or _player.combatant == null:
		return
	var status := _player.combatant.status
	var ids := status.active_ids()
	var elixir_text := _elixir_text()
	var signature: Array = []
	for effect_id in ids:
		signature.append("%s:%d" % [effect_id, status.stacks(effect_id)])
	signature.append("elixir:" + elixir_text)
	var key := ",".join(signature)

	if key != _buff_signature:
		_buff_signature = key
		GameWindow.clear_children(_buff_box)
		for effect_id in ids:
			_buff_box.add_child(_make_buff_chip(str(effect_id)))
		if elixir_text != "":
			_buff_box.add_child(_make_elixir_chip(elixir_text))
	for chip in _buff_box.get_children():
		if str(chip.name) == "elixir":
			continue
		var effect_id := str(chip.name)
		var label := chip.get_child(0) as Label
		var seconds := ceili(status.remaining(effect_id))
		var count := status.stacks(effect_id)
		var effect_name := str(DataRegistry.get_status_effect(effect_id).get("name", effect_id))
		label.text = "%s%s %ds" % [effect_name, (" x%d" % count) if count > 1 else "", seconds]


func _elixir_text() -> String:
	var elixir: Dictionary = Session.character.get("elixir", {})
	var now := _player.now_unix()
	if not ElixirRules.is_active(elixir, now):
		return ""
	var definition: Dictionary = ElixirRules.types().get(str(elixir.get("id", "")), {})
	return "%s %s" % [str(definition.get("name", "Elixir")), ElixirRules.time_text(ElixirRules.seconds_left(elixir, now))]


func _make_elixir_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.name = "elixir"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TSMTheme.PANEL, 0.9)
	style.border_color = Color("ffd23f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("ffd23f"))
	chip.add_child(label)
	return chip


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
