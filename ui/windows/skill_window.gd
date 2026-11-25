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


func setup() -> void:
	build("SKILLS")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	body.add_child(top)
	_class_label = Label.new()
	_class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_label.add_theme_font_size_override("font_size", 26)
	_class_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	top.add_child(_class_label)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 26)
	top.add_child(_points_label)
	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(140, 56)
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
		tab.custom_minimum_size = Vector2(0, 60)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 22)
		tab.pressed.connect(show_tab.bind(index))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	(_tab_buttons[0] as Button).button_pressed = true

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)
	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	columns.add_child(left)
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	left_scroll.add_child(_list)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 8)
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
	_main_button.custom_minimum_size = Vector2(0, 72)
	_main_button.add_theme_font_size_override("font_size", 26)
	_main_button.pressed.connect(_on_main)
	right_box.add_child(_main_button)

	var slots_label := Label.new()
	slots_label.text = "Slots  -  select a skill, then tap a slot to put it there (tap it again to remove)"
	slots_label.add_theme_font_size_override("font_size", 17)
	slots_label.add_theme_color_override("font_color", TSMTheme.MUTED)
	body.add_child(slots_label)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	body.add_child(slots)
	for slot_name in SkillDB.SLOT_NAMES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 84)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(_on_slot.bind(str(slot_name)))
		slots.add_child(button)
		_slot_buttons[slot_name] = button

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 20)
	body.add_child(_message)
	Session.character_changed.connect(func() -> void:
		if visible:
			refresh())


func open() -> void:
	_message.text = ""
	super.open()


## Switches to a tab: 0 to 2 are the class's paths, 3 is the special attack and ultimate.
func show_tab(index: int) -> void:
	_tab = index
	_selected_skill = ""
	_selected_ability = ""
	_message.text = ""
	(_tab_buttons[index] as Button).set_pressed_no_signal(true)
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
	button.custom_minimum_size = Vector2(0, 72)
	button.add_theme_font_size_override("font_size", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, color)
	if skill_id == _selected_skill:
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, slot_style(TSMTheme.ACCENT, true))
	button.pressed.connect(select_skill.bind(skill_id))
	return button


func _ability_row(ability: Dictionary) -> Button:
	var ability_id := str(ability["ability_id"])
	var rank := SkillBook.ability_rank(Session.character, ability_id)
	var status := "Level %d" % int(ability["unlock_level"]) if rank == 0 else "Rank %d / %d" % [rank, int(ability["rank_max"])]
	var button := Button.new()
	button.text = "%s: %s      %s" % ["Ultimate" if str(ability.get("ability_type", "")) == "ultimate" else "Special", str(ability["ability_name"]), status]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 72)
	button.add_theme_font_size_override("font_size", 22)
	var color := TSMTheme.MUTED if rank == 0 else TSMTheme.TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, color)
	if ability_id == _selected_ability:
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, slot_style(TSMTheme.ACCENT, true))
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
		hint.add_theme_color_override("font_color", TSMTheme.MUTED)
		_details.add_child(hint)


func _add_line(text: String, color: Color, size: int = 20) -> void:
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
	_add_line(SkillDB.skill_name(skill_id), TSMTheme.ACCENT, 28)
	_add_line("Rank %d / %d" % [rank, maximum] if rank > 0 else "Not learned", TSMTheme.TEXT, 22)
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
	_add_line(str(data["ability_name"]), TSMTheme.ACCENT, 28)
	_add_line("Locked  -  reach level %d" % int(data["unlock_level"]) if rank == 0 else "Rank %d / %d" % [rank, int(data["rank_max"])], TSMTheme.TEXT, 22)
	for line in SkillDB.describe_ability(ability_id, maxi(rank, 1)):
		_add_line(str(line["text"]), _line_color(str(line["kind"])))
	if rank == 0:
		_add_line(str(data.get("unlock_requirement", "")), TSMTheme.MUTED, 18)
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
		button.text = "%s\n%s" % [number, _initials(skill_id)] if skill_id != "" else "%s\n-" % number
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
