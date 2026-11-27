class_name SkillWindow
extends GameWindow
## The skill window: one tab for each of your class's three paths (six skills
## each, learned in order) and a tab for the special attack and ultimate. Learn
## or rank up with skill points, and put learned skills on the eight slots below.
## It shows and asks; the points and slots change through Session.

var _tab: int = 0
var _selected_skill: String = ""
var _selected_ability: String = ""

var _class_label: Label
var _points_label: Label
var _tab_buttons: Array = []
var _list: VBoxContainer
var _details: VBoxContainer
var _main_button: Button
var _slot_buttons: Dictionary = {}
var _message: Label


func _card_style(accent: Color = TSMTheme.BORDER, bg_alpha: float = 0.86, radius: int = 10, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("120824", bg_alpha)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


func _tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2b1452", 0.95) if active else Color("160a2b", 0.85)
	style.border_color = TSMTheme.ACCENT if active else Color("5b2a8c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _action_button_style(accent: Color = TSMTheme.ACCENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a1352", 0.96)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _apply_window_size() -> void:
	var vp := get_viewport_rect().size
	var target_w := clampf(vp.x - 136.0, 920.0, 1180.0) if vp.x > 0.0 else 1120.0
	var target_h := clampf(vp.y - 60.0, 540.0, 668.0) if vp.y > 0.0 else 652.0
	custom_minimum_size = Vector2(target_w, target_h)
	size = Vector2(target_w, target_h)
	if vp.x > 0.0 and vp.y > 0.0:
		position = Vector2((vp.x - size.x) * 0.5, (vp.y - size.y) * 0.5)


func setup() -> void:
	build("SKILLS")
	_apply_window_size()

	var header_card := PanelContainer.new()
	header_card.add_theme_stylebox_override("panel", _card_style(Color("8a5fd0"), 0.9, 10, 10))
	body.add_child(header_card)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	header_card.add_child(top)
	_class_label = Label.new()
	_class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_label.add_theme_font_size_override("font_size", 24)
	_class_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	top.add_child(_class_label)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 21)
	_points_label.add_theme_color_override("font_color", Color("ffd23f"))
	top.add_child(_points_label)
	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(132, 46)
	reset.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "focus"]:
		reset.add_theme_stylebox_override(state, _action_button_style(Color("9c6ade")))
	reset.pressed.connect(_on_reset)
	top.add_child(reset)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for index in 4:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 50)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 19)
		tab.pressed.connect(show_tab.bind(index))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	(_tab_buttons[0] as Button).button_pressed = true
	_refresh_tab_styles()

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	body.add_child(columns)

	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	left.add_theme_stylebox_override("panel", _card_style(TSMTheme.BORDER, 0.84, 10, 12))
	columns.add_child(left)
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(left_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	left_scroll.add_child(_list)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.95
	right.add_theme_stylebox_override("panel", _card_style(Color("8a5fd0"), 0.86, 10, 14))
	columns.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right.add_child(right_box)
	var details_scroll := ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(details_scroll)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override("separation", 6)
	details_scroll.add_child(_details)
	_main_button = Button.new()
	_main_button.custom_minimum_size = Vector2(0, 58)
	_main_button.add_theme_font_size_override("font_size", 21)
	for state in ["normal", "hover", "pressed", "focus"]:
		_main_button.add_theme_stylebox_override(state, _action_button_style(TSMTheme.ACCENT))
	_main_button.pressed.connect(_on_main)
	right_box.add_child(_main_button)

	var slots_label := Label.new()
	slots_label.text = "Slots  -  select a skill, then tap a slot to assign or remove its full skill name"
	slots_label.add_theme_font_size_override("font_size", 15)
	slots_label.add_theme_color_override("font_color", TSMTheme.MUTED)
	body.add_child(slots_label)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	body.add_child(slots)
	for slot_name in SkillDB.SLOT_NAMES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 86)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(_on_slot.bind(str(slot_name)))
		slots.add_child(button)
		_slot_buttons[slot_name] = button

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 18)
	body.add_child(_message)
	Session.character_changed.connect(func() -> void:
		if visible:
			refresh())


func _refresh_tab_styles() -> void:
	for index in _tab_buttons.size():
		var tab := _tab_buttons[index] as Button
		var is_active := index == _tab
		var style := _tab_style(is_active)
		for state in ["normal", "hover", "pressed", "focus"]:
			tab.add_theme_stylebox_override(state, style)
		for color_state in ["font_color", "font_hover_color", "font_pressed_color"]:
			tab.add_theme_color_override(color_state, TSMTheme.ACCENT if is_active else TSMTheme.TEXT)


func open() -> void:
	_apply_window_size()
	_message.text = ""
	super.open()


## Switches to a tab: 0 to 2 are the class's paths, 3 is the special attack and ultimate.
func show_tab(index: int) -> void:
	_tab = index
	_selected_skill = ""
	_selected_ability = ""
	_message.text = ""
	(_tab_buttons[index] as Button).set_pressed_no_signal(true)
	_refresh_tab_styles()
	refresh()


func select_skill(skill_id: String) -> void:
	_selected_skill = skill_id
	_selected_ability = ""
	_message.text = ""
	refresh()


func select_ability(ability_id: String) -> void:
	_selected_ability = ability_id
	_selected_skill = ""
	_message.text = ""
	refresh()


func _class_id() -> String:
	return str(Session.character.get("class_id", ""))


func _record() -> Dictionary:
	return SkillBook.normalize(Session.character.get("skills"), _class_id())


# ---------- drawing ----------

func refresh() -> void:
	if _list == null or not Session.has_character():
		return
	var class_id := _class_id()
	var paths := SkillDB.paths_for_class(class_id)
	_class_label.text = "%s   Level %d" % [str(DataRegistry.get_class_data(class_id).get("display_name", class_id.capitalize())), int(Session.character.get("level", 1))]
	_points_label.text = "Skill points: %d" % SkillBook.available_points(Session.character)
	for index in 3:
		(_tab_buttons[index] as Button).text = str(paths[index]["path_name"]) if index < paths.size() else "-"
		(_tab_buttons[index] as Button).visible = index < paths.size()
	(_tab_buttons[3] as Button).text = "Ultimate"
	_refresh_tab_styles()

	clear_children(_list)
	if _tab < 3:
		if _tab < paths.size():
			for skill_id in paths[_tab]["skill_ids"]:
				_list.add_child(_skill_row(str(skill_id)))
	else:
		for ability in [SkillDB.special_for_class(class_id), SkillDB.ultimate_for_class(class_id)]:
			if not ability.is_empty():
				_list.add_child(_ability_row(ability))
	_refresh_details()
	_refresh_slots()


func _skill_row(skill_id: String) -> Button:
	var rank := SkillBook.rank_of(_record(), skill_id)
	var code := SkillBook.learn_error(Session.character, skill_id)
	var status := ""
	var color := TSMTheme.MUTED
	if rank >= SkillDB.max_rank(skill_id):
		status = "Rank %d  (max)" % rank
		color = TSMTheme.ACCENT
	elif rank > 0:
		status = "Rank %d / %d" % [rank, SkillDB.max_rank(skill_id)]
		color = TSMTheme.TEXT
	elif code == "":
		status = "Ready to learn"
		color = TSMTheme.OK
	elif code == "LEVEL_TOO_LOW":
		status = "Level %d" % SkillDB.unlock_level(skill_id)
	elif code == "PREREQUISITE":
		status = "Locked"
	else:
		status = "%d points" % SkillDB.point_cost(skill_id)
		color = Color("d8b04a")
	var button := Button.new()
	button.text = "%s      %s" % [SkillDB.skill_name(skill_id), status]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 60)
	button.add_theme_font_size_override("font_size", 19)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, color)
	var is_selected := skill_id == _selected_skill
	var row_style := slot_style(TSMTheme.ACCENT if is_selected else Color("4a2273"), is_selected, is_selected)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, row_style)
	button.pressed.connect(select_skill.bind(skill_id))
	return button


func _ability_row(ability: Dictionary) -> Button:
	var ability_id := str(ability["ability_id"])
	var rank := SkillBook.ability_rank(Session.character, ability_id)
	var status := "Level %d" % int(ability["unlock_level"]) if rank == 0 else "Rank %d / %d" % [rank, int(ability["rank_max"])]
	var button := Button.new()
	button.text = "%s: %s      %s" % ["Ultimate" if str(ability.get("ability_type", "")) == "ultimate" else "Special", str(ability["ability_name"]), status]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 60)
	button.add_theme_font_size_override("font_size", 19)
	var color := TSMTheme.MUTED if rank == 0 else TSMTheme.TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, color)
	var is_selected := ability_id == _selected_ability
	var row_style := slot_style(TSMTheme.ACCENT if is_selected else Color("4a2273"), is_selected, is_selected)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, row_style)
	button.pressed.connect(select_ability.bind(ability_id))
	return button


func _refresh_details() -> void:
	clear_children(_details)
	_main_button.visible = false
	if _selected_skill != "":
		_show_skill(_selected_skill)
	elif _selected_ability != "":
		_show_ability(_selected_ability)
	else:
		var hint := Label.new()
		hint.text = "Tap a skill to see it."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", TSMTheme.MUTED)
		_details.add_child(hint)


func _add_line(text: String, color: Color, size: int = 19) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_details.add_child(label)


func _line_color(kind: String) -> Color:
	match kind:
		"damage":
			return Color("ff9a6b")
		"effect":
			return Color("8fd0ff")
	return TSMTheme.TEXT


func _show_skill(skill_id: String) -> void:
	var rank := SkillBook.rank_of(_record(), skill_id)
	var maximum := SkillDB.max_rank(skill_id)
	_add_line(SkillDB.skill_name(skill_id), TSMTheme.ACCENT, 26)
	_add_line("Rank %d / %d" % [rank, maximum] if rank > 0 else "Not learned", TSMTheme.TEXT, 20)
	for line in SkillDB.describe(skill_id, maxi(rank, 1)):
		_add_line(str(line["text"]), _line_color(str(line["kind"])))
	if rank > 0 and rank < maximum:
		for line in SkillDB.describe(skill_id, rank + 1):
			if line["kind"] == "damage":
				_add_line("Next rank:  " + str(line["text"]), Color("7be07b"))
		_add_line("Next rank cooldown: %s s" % SkillDB._trim(SkillDB.cooldown_at_rank(skill_id, rank + 1)), Color("7be07b"))
	var slot := SkillBook.equipped_slot(_record(), skill_id)
	if slot != "":
		_add_line("On slot %s" % slot.trim_prefix("skill_"), TSMTheme.OK)

	var code := SkillBook.learn_error(Session.character, skill_id)
	_main_button.visible = rank < maximum
	_main_button.text = "%s  (%d points)" % ["Rank up" if rank > 0 else "Learn", SkillDB.point_cost(skill_id)]
	_main_button.disabled = code != ""
	if code != "" and rank < maximum:
		_add_line(SkillBook.message_for(code, skill_id), TSMTheme.ERROR)


func _show_ability(ability_id: String) -> void:
	var data := SkillDB.ability(ability_id)
	var rank := SkillBook.ability_rank(Session.character, ability_id)
	_add_line(str(data["ability_name"]), TSMTheme.ACCENT, 26)
	_add_line("Locked  -  reach level %d" % int(data["unlock_level"]) if rank == 0 else "Rank %d / %d" % [rank, int(data["rank_max"])], TSMTheme.TEXT, 20)
	for line in SkillDB.describe_ability(ability_id, maxi(rank, 1)):
		_add_line(str(line["text"]), _line_color(str(line["kind"])))
	if rank == 0:
		_add_line(str(data.get("unlock_requirement", "")), TSMTheme.MUTED, 17)
	var code := SkillBook.ability_error(Session.character, ability_id)
	_main_button.visible = rank > 0 and rank < int(data["rank_max"])
	_main_button.text = "Rank up  (%d points)" % int(DataRegistry.get_config("skill_rules").get("ability_rank_cost", 8))
	_main_button.disabled = code != ""
	if code == "NOT_ENOUGH_POINTS" and _main_button.visible:
		_add_line("Not enough skill points.", TSMTheme.ERROR)


func _refresh_slots() -> void:
	var record := _record()
	for slot_name in SkillDB.SLOT_NAMES:
		var button: Button = _slot_buttons[slot_name]
		var skill_id := str(record["slots"].get(slot_name, ""))
		var number := str(slot_name).trim_prefix("skill_")
		button.text = "%s\n%s" % [number, _slot_skill_words(skill_id)] if skill_id != "" else "%s\n-" % number
		var selected := skill_id != "" and skill_id == _selected_skill
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, slot_style(TSMTheme.ACCENT if selected else Color("5b2a8c"), selected, skill_id != ""))


static func _initials(skill_id: String) -> String:
	var letters := ""
	for word in SkillDB.skill_name(skill_id).replace("'", "").split(" ", false):
		letters += word.substr(0, 1).to_upper()
		if letters.length() >= 2:
			break
	return letters


static func _slot_skill_words(skill_id: String) -> String:
	var raw := SkillDB.skill_name(skill_id).strip_edges()
	if raw == "":
		raw = skill_id.replace("_", " ").replace("-", " ").strip_edges()
	var words := PackedStringArray()
	for part in raw.split(" ", false):
		if part.length() > 0:
			words.append(part.substr(0, 1).to_upper() + part.substr(1))
	var joined := " ".join(words).strip_edges()
	if joined.length() > 16:
		return joined.substr(0, 15).strip_edges() + "…"
	return joined


# ---------- buttons ----------

func _on_main() -> void:
	var result: Dictionary
	if _selected_skill != "":
		result = Session.learn_skill(_selected_skill)
		if result["ok"]:
			_show_result("%s %s (rank %d)." % ["Learned" if int(result.get("rank", 1)) == 1 else "Raised", SkillDB.skill_name(_selected_skill), int(result.get("rank", 1))], true)
	elif _selected_ability != "":
		result = Session.rank_up_ability(_selected_ability)
		if result["ok"]:
			_show_result("%s is now rank %d." % [str(SkillDB.ability(_selected_ability)["ability_name"]), int(result.get("rank", 1))], true)
	else:
		return
	if not result["ok"]:
		_show_result(str(result.get("message", "That did not work.")), false)


func _on_slot(slot_name: String) -> void:
	var on_slot := str(_record()["slots"].get(slot_name, ""))
	if _selected_skill == "":
		if on_slot != "":
			select_skill(on_slot)            # tapping a filled slot shows that skill
		return
	if on_slot == _selected_skill:
		Session.unequip_skill(slot_name)
		_show_result("Removed from slot %s." % slot_name.trim_prefix("skill_"), true)
		return
	var result = Session.equip_skill(_selected_skill, slot_name)
	if result["ok"]:
		_show_result("%s is on slot %s." % [SkillDB.skill_name(_selected_skill), slot_name.trim_prefix("skill_")], true)
	else:
		_show_result(str(result.get("message", "That did not work.")), false)


func _on_reset() -> void:
	var result = Session.reset_skills()
	_selected_skill = ""
	_selected_ability = ""
	_show_result("All skills reset. Your points are back." if result["ok"] else str(result.get("message", "")), result["ok"])


func _show_result(text: String, good: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", TSMTheme.OK if good else TSMTheme.ERROR)
