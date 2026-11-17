class_name CharacterWindow
extends GameWindow
## The character screen. Stats tab: level and EXP, attribute points, and the full
## stat table (base, gear, final). Equipment tab: every slot with what is worn.
## Sign Out lives here too.

signal sign_out_requested

var _stats_page: Control
var _equipment_page: Control
var _tab_buttons: Dictionary = {}

var _header: Label
var _exp_bar: ProgressBar
var _exp_label: Label
var _points_label: Label
var _attribute_box: VBoxContainer
var _stats_grid: VBoxContainer

var _slot_box: VBoxContainer
var _slot_details: VBoxContainer
var _potions_page: Control
var _quick_rows: Dictionary = {}        # resource -> {"label", "clear"}
var _auto_controls: Array = []          # [{"check", "slider", "value", "auto_key", "percent_key"}]
var _elixir_label: Label
var _message: Label


func setup() -> void:
	build("CHARACTER")
	_build_layout()
	Session.character_changed.connect(func() -> void:
		if visible:
			refresh())


func _build_layout() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for page in ["Stats", "Equipment", "Potions"]:
		var tab := Button.new()
		tab.text = page
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(200, 60)
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(_show_page.bind(page))
		tabs.add_child(tab)
		_tab_buttons[page] = tab
	(_tab_buttons["Stats"] as Button).button_pressed = true

	_stats_page = _build_stats_page()
	_equipment_page = _build_equipment_page()
	_potions_page = _build_potions_page()
	body.add_child(_stats_page)
	body.add_child(_equipment_page)
	body.add_child(_potions_page)
	_equipment_page.visible = false
	_potions_page.visible = false

	var footer := HBoxContainer.new()
	body.add_child(footer)
	_message = Label.new()
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_message)
	var sign_out := Button.new()
	sign_out.text = "Sign Out"
	sign_out.custom_minimum_size = Vector2(220, 64)
	sign_out.add_theme_font_size_override("font_size", 22)
	sign_out.pressed.connect(func() -> void: sign_out_requested.emit())
	footer.add_child(sign_out)


func _build_stats_page() -> Control:
	var page := HBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(620, 0)
	page.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left.add_child(left_box)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 28)
	_header.add_theme_color_override("font_color", TSMTheme.ACCENT)
	left_box.add_child(_header)
	_exp_bar = ProgressBar.new()
	_exp_bar.show_percentage = false
	_exp_bar.min_value = 0.0
	_exp_bar.max_value = 1.0
	_exp_bar.step = 0.00001
	_exp_bar.custom_minimum_size = Vector2(0, 16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("8fd0ff")
	fill.set_corner_radius_all(4)
	_exp_bar.add_theme_stylebox_override("fill", fill)
	left_box.add_child(_exp_bar)
	_exp_label = Label.new()
	_exp_label.add_theme_font_size_override("font_size", 18)
	_exp_label.add_theme_color_override("font_color", TSMTheme.MUTED)
	left_box.add_child(_exp_label)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 24)
	left_box.add_child(_points_label)
	_attribute_box = VBoxContainer.new()
	_attribute_box.add_theme_constant_override("separation", 6)
	left_box.add_child(_attribute_box)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_stats_grid = VBoxContainer.new()
	_stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_grid.add_theme_constant_override("separation", 4)
	scroll.add_child(_stats_grid)
	return page


func _build_equipment_page() -> Control:
	var page := HBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)

	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_slot_box = VBoxContainer.new()
	_slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_slot_box)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(500, 0)
	page.add_child(right)
	var details_scroll := ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(details_scroll)
	_slot_details = VBoxContainer.new()
	_slot_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_details.add_theme_constant_override("separation", 6)
	details_scroll.add_child(_slot_details)
	return page


func _build_potions_page() -> Control:
	var page := PanelContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)

	box.add_child(_heading("Quick-use slots"))
	for resource in DataRegistry.get_config("consumable_rules").get("quick_slots", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var slot_label := Label.new()
		slot_label.text = str(resource).capitalize()
		slot_label.custom_minimum_size = Vector2(160, 0)
		slot_label.add_theme_color_override("font_color", TSMTheme.MUTED)
		row.add_child(slot_label)
		var item_label := Label.new()
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_label)
		var clear := Button.new()
		clear.text = "Clear"
		clear.custom_minimum_size = Vector2(130, 56)
		clear.pressed.connect(_on_clear_slot.bind(str(resource)))
		row.add_child(clear)
		box.add_child(row)
		_quick_rows[resource] = {"label": item_label, "clear": clear}
	var hint := Label.new()
	hint.text = "To set a slot: open your Bag, select a potion, and tap Quick slot."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", TSMTheme.MUTED)
	box.add_child(hint)

	box.add_child(_heading("Auto Pots"))
	for entry in [["Auto HP", "auto_hp", "hp_percent"], ["Auto MP", "auto_mp", "mp_percent"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var check := CheckButton.new()
		check.text = str(entry[0])
		check.custom_minimum_size = Vector2(220, 56)
		check.add_theme_font_size_override("font_size", 22)
		check.toggled.connect(_on_auto_toggled.bind(str(entry[1])))
		row.add_child(check)
		var slider := HSlider.new()
		slider.min_value = 5
		slider.max_value = 95
		slider.step = 5
		slider.custom_minimum_size = Vector2(320, 44)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_auto_percent.bind(str(entry[2])))
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size = Vector2(90, 0)
		value.add_theme_font_size_override("font_size", 22)
		row.add_child(value)
		box.add_child(row)
		_auto_controls.append({"check": check, "slider": slider, "value": value,
				"auto_key": str(entry[1]), "percent_key": str(entry[2])})
	var auto_hint := Label.new()
	auto_hint.text = "Drinks a potion by itself when health or mana falls to the limit. Each potion has its own cooldown."
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_hint.add_theme_font_size_override("font_size", 17)
	auto_hint.add_theme_color_override("font_color", TSMTheme.MUTED)
	box.add_child(auto_hint)

	box.add_child(_heading("Elixir"))
	_elixir_label = Label.new()
	_elixir_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_elixir_label)
	return page


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	return label


func _refresh_potions() -> void:
	var settings: Dictionary = Session.character.get("settings", {})
	var quick: Dictionary = settings.get("quick_slots", {})
	for resource in _quick_rows:
		var item_id := str(quick.get(resource, ""))
		var label: Label = _quick_rows[resource]["label"]
		var clear: Button = _quick_rows[resource]["clear"]
		if item_id == "":
			label.text = "(empty)"
			label.add_theme_color_override("font_color", Color("5d5470"))
		else:
			label.text = "%s   x%d" % [ItemDB.display_name(item_id), Inventory.count(Session.character.get("inventory", []), item_id)]
			label.add_theme_color_override("font_color", TSMTheme.rarity_color(ItemDB.rarity(item_id)))
		clear.disabled = item_id == ""
	for control in _auto_controls:
		(control["check"] as CheckButton).set_pressed_no_signal(bool(settings.get(control["auto_key"], false)))
		var percent := int(settings.get(control["percent_key"], 50))
		(control["slider"] as HSlider).set_value_no_signal(percent)
		(control["value"] as Label).text = "%d%%" % percent

	var elixir: Dictionary = Session.character.get("elixir", {})
	var now := int(Time.get_unix_time_from_system())
	if ElixirRules.is_active(elixir, now):
		var definition: Dictionary = ElixirRules.types().get(str(elixir.get("id", "")), {})
		_elixir_label.text = "%s  -  %s left" % [str(definition.get("name", elixir.get("id", "Elixir"))),
				ElixirRules.time_text(ElixirRules.seconds_left(elixir, now))]
		_elixir_label.add_theme_color_override("font_color", Color("ffd23f"))
	else:
		_elixir_label.text = "No elixir active."
		_elixir_label.add_theme_color_override("font_color", TSMTheme.MUTED)


func _on_clear_slot(resource: String) -> void:
	Session.set_quick_slot(resource, "")


func _on_auto_toggled(pressed: bool, key: String) -> void:
	Session.update_settings({key: pressed})


func _on_auto_percent(value: float, key: String) -> void:
	Session.update_settings({key: int(value)})


func _show_page(page: String) -> void:
	_stats_page.visible = page == "Stats"
	_equipment_page.visible = page == "Equipment"
	_potions_page.visible = page == "Potions"
	refresh()


# ---------- drawing ----------

func refresh() -> void:
	if _header == null or not Session.has_character():
		return
	if _stats_page.visible:
		_refresh_stats()
	elif _equipment_page.visible:
		_refresh_equipment()
	else:
		_refresh_potions()


func _refresh_stats() -> void:
	var c := Session.character
	var level := int(c.get("level", 1))
	_header.text = "%s  -  %s" % [str(c.get("name", "?")), str(c.get("class_id", "?")).capitalize()]
	_exp_bar.value = StatDisplay.exp_fraction(level, int(c.get("exp", 0)), int(c.get("rebirth", 0)))
	_exp_label.text = StatDisplay.exp_text(level, int(c.get("exp", 0)), int(c.get("rebirth", 0)))
	var points := int(c.get("stat_points", 0))
	_points_label.text = "Stat points: %d" % points
	_points_label.add_theme_color_override("font_color", TSMTheme.ACCENT if points > 0 else TSMTheme.MUTED)

	clear_children(_attribute_box)
	var totals := StatCalculator.attribute_totals(str(c.get("class_id", "")), c.get("attributes", {}))
	for attribute in StatCalculator.ATTRIBUTES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.text = "%s  (%s)" % [str(StatDisplay.ATTRIBUTE_NAMES.get(attribute, attribute)), attribute.to_upper()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 22)
		row.add_child(name_label)
		var value := Label.new()
		value.text = str(int(totals[attribute]))
		value.custom_minimum_size = Vector2(70, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 22)
		row.add_child(value)
		for amount in [1, 5]:
			var button := Button.new()
			button.text = "+%d" % amount
			button.custom_minimum_size = Vector2(80, 56)
			button.disabled = points < amount
			button.pressed.connect(_on_spend.bind(str(attribute), amount))
			row.add_child(button)
		_attribute_box.add_child(row)

	clear_children(_stats_grid)
	var result := Session.total_stats(false)
	if not result["ok"]:
		return
	for group in StatDisplay.GROUPS:
		var heading := Label.new()
		heading.text = str(group[0])
		heading.add_theme_font_size_override("font_size", 22)
		heading.add_theme_color_override("font_color", TSMTheme.ACCENT)
		_stats_grid.add_child(heading)
		for stat in group[1]:
			if not result["stats"].has(stat):
				continue
			var row := HBoxContainer.new()
			var stat_label := Label.new()
			stat_label.text = StatDisplay.stat_name(str(stat))
			stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stat_label.add_theme_color_override("font_color", TSMTheme.MUTED)
			row.add_child(stat_label)
			var bonus := float(result["equipment_bonus"][stat])
			if bonus != 0.0:
				var gear_label := Label.new()
				gear_label.text = "(%s)" % StatDisplay.format_bonus(str(stat), bonus)
				gear_label.add_theme_font_size_override("font_size", 17)
				gear_label.add_theme_color_override("font_color", TSMTheme.OK)
				row.add_child(gear_label)
			var final_label := Label.new()
			final_label.text = StatDisplay.format_stat(str(stat), result["stats"][stat])
			final_label.custom_minimum_size = Vector2(120, 0)
			final_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(final_label)
			_stats_grid.add_child(row)


func _refresh_equipment() -> void:
	clear_children(_slot_box)
	var worn: Dictionary = Session.character.get("equipment", {})
	for slot in Equipment.slots():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var slot_label := Label.new()
		slot_label.text = ItemInfo.slot_label(str(slot))
		slot_label.custom_minimum_size = Vector2(150, 0)
		slot_label.add_theme_color_override("font_color", TSMTheme.MUTED)
		row.add_child(slot_label)

		var item_label := Label.new()
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_label)
		if worn.has(slot):
			var item_id := str(worn[slot].get("item_id", ""))
			item_label.text = ItemDB.display_name(item_id)
			item_label.add_theme_color_override("font_color", TSMTheme.rarity_color(ItemDB.rarity(item_id)))
			var details := Button.new()
			details.text = "Details"
			details.custom_minimum_size = Vector2(130, 56)
			details.pressed.connect(_on_details.bind(item_id))
			row.add_child(details)
			var take_off := Button.new()
			take_off.text = "Take off"
			take_off.custom_minimum_size = Vector2(150, 56)
			take_off.pressed.connect(_on_take_off.bind(str(slot)))
			row.add_child(take_off)
		else:
			item_label.text = "(empty)"
			item_label.add_theme_color_override("font_color", Color("5d5470"))
		_slot_box.add_child(row)

	if _slot_details.get_child_count() == 0:
		var hint := Label.new()
		hint.text = "Tap Details to see a piece of gear."
		hint.add_theme_color_override("font_color", TSMTheme.MUTED)
		_slot_details.add_child(hint)


# ---------- buttons ----------

func _on_spend(attribute: String, amount: int) -> void:
	var result := Session.allocate_attribute(attribute, amount)
	_message.text = "" if result["ok"] else str(result.get("message", "Could not spend points."))
	_message.add_theme_color_override("font_color", TSMTheme.ERROR)


func _on_details(item_id: String) -> void:
	var holder := VBoxContainer.new()
	fill_item_lines(holder, item_id)
	clear_children(_slot_details)
	_slot_details.add_child(holder)


func _on_take_off(slot: String) -> void:
	var result := Session.unequip_item(slot)
	_message.text = "" if result["ok"] else str(result.get("message", "Could not take it off."))
	_message.add_theme_color_override("font_color", TSMTheme.ERROR)
	clear_children(_slot_details)
