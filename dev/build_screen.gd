extends Control
## DEV SCREEN: try out your character's build. Spend attribute points, add items,
## wear and remove gear, and watch the stats change: base (class + level +
## points), what the gear adds, and the final number.
## Changes are saved to your character in the cloud unless you untick "Save".
## Never ship this folder (exclude "dev/*" in the export settings).

var _status: Label
var _save_check: CheckBox
var _mount_check: CheckBox
var _summary: Label
var _attribute_box: VBoxContainer
var _bag_box: VBoxContainer
var _worn_box: VBoxContainer
var _stats_grid: GridContainer
var _item_picker: OptionButton
var _picker_ids: Array = []


func _ready() -> void:
	theme = TSMTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if Session.has_signal("character_changed"):
		if not Session.is_connected("character_changed", _refresh):
			Session.character_changed.connect(_refresh)
	if Session.has_character():
		_refresh()
	else:
		_load_character()


func _load_character() -> void:
	_say("Loading your character...")
	var restored: Dictionary = await FirebaseService.try_restore_session()
	if not restored["ok"]:
		_say("Not signed in. Sign in with the game first, then open this screen again.", true)
		return
	var loaded: Dictionary = await Session.load_character(1)
	if not loaded["ok"] or not loaded["found"]:
		_say("No character in slot 1. Create one first.", true)
		return
	_refresh()


# ---------- layout ----------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = TSMTheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	root.add_child(header)
	var title := Label.new()
	title.text = "BUILD TEST"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TSMTheme.ACCENT)
	header.add_child(title)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_summary)
	_mount_check = CheckBox.new()
	_mount_check.text = "Riding mount"
	_mount_check.toggled.connect(func(_on: bool) -> void: _refresh())
	header.add_child(_mount_check)
	_save_check = CheckBox.new()
	_save_check.text = "Save to cloud"
	_save_check.button_pressed = true
	_save_check.toggled.connect(func(on: bool) -> void: Session.save_enabled = on)
	header.add_child(_save_check)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)
	columns.add_child(_column("Build", _build_attribute_column()))
	columns.add_child(_column("Items", _build_item_column()))
	columns.add_child(_column("Stats", _build_stats_column()))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 30)
	root.add_child(_status)


func _column(title_text: String, content: Control) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	panel.add_child(box)
	var heading := Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return panel


func _build_attribute_column() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_attribute_box = VBoxContainer.new()
	_attribute_box.add_theme_constant_override("separation", 6)
	box.add_child(_attribute_box)
	var exp_row := HBoxContainer.new()
	exp_row.add_theme_constant_override("separation", 8)
	box.add_child(exp_row)
	for amount in [100, 10000, 1000000]:
		var button := Button.new()
		button.text = "+%d EXP" % amount
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var current_amount: int = amount
		button.pressed.connect(func() -> void: await _on_exp(current_amount))
		exp_row.add_child(button)
	return box


func _build_item_column() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 8)
	box.add_child(picker_row)
	_item_picker = OptionButton.new()
	_item_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item_id in DataRegistry.get_ids("items"):
		var category := ItemDB.category(item_id)
		if ItemDB.equip_slot(item_id) != "" or category == "consumable":
			_picker_ids.append(item_id)
			_item_picker.add_item("%s  (%s)" % [ItemDB.display_name(item_id), category])
	picker_row.add_child(_item_picker)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(_on_add_selected)
	picker_row.add_child(add)

	var add_all := Button.new()
	add_all.text = "Add one of every piece of gear"
	add_all.pressed.connect(_on_add_all_gear)
	box.add_child(add_all)

	box.add_child(_small_heading("In the bag"))
	_bag_box = VBoxContainer.new()
	box.add_child(_bag_box)
	box.add_child(_small_heading("Worn"))
	_worn_box = VBoxContainer.new()
	box.add_child(_worn_box)
	return box


func _build_stats_column() -> Control:
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 18)
	return _stats_grid


func _small_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TSMTheme.MUTED)
	return label


# ---------- refresh ----------

func _refresh() -> void:
	if not Session.has_character():
		return
	var c := Session.character
	_summary.text = "%s  |  %s  |  Level %d  |  EXP %d  |  Stat points: %d" % [
			str(c.get("name", "?")), str(c.get("class_id", "?")).capitalize(),
			int(c.get("level", 1)), int(c.get("exp", 0)), int(c.get("stat_points", 0))]
	_refresh_attributes()
	_refresh_items()
	_refresh_stats()


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _refresh_attributes() -> void:
	_clear(_attribute_box)
	var totals := StatCalculator.attribute_totals(str(Session.character.get("class_id", "")),
			Session.character.get("attributes", {}))
	var labels: Dictionary = DataRegistry.get_config("stat_rules").get("attributes", {})
	for attribute in StatCalculator.ATTRIBUTES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.text = "%s  (%s)" % [str(labels.get(attribute, {}).get("label", attribute)), attribute.to_upper()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value := Label.new()
		value.text = "%d" % int(totals[attribute])
		value.custom_minimum_size = Vector2(60, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		for amount in [1, 5]:
			var button := Button.new()
			button.text = "+%d" % amount
			button.custom_minimum_size = Vector2(70, 0)
			button.pressed.connect(_on_spend.bind(attribute, amount))
			row.add_child(button)
		_attribute_box.add_child(row)


func _refresh_items() -> void:
	_clear(_bag_box)
	var bag: Array = Session.character.get("inventory", [])
	if bag.is_empty():
		_bag_box.add_child(_small_heading("(empty)"))
	for entry in bag:
		var item_id := str(entry.get("item_id", ""))
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry.has("uid"):
			label.text = "%s  [%s]" % [ItemDB.display_name(item_id), ItemDB.equip_slot(item_id)]
		else:
			label.text = "%s  x%d" % [ItemDB.display_name(item_id), int(entry.get("qty", 1))]
		row.add_child(label)
		if entry.has("uid") and ItemDB.equip_slot(item_id) != "":
			var wear := Button.new()
			wear.text = "Wear"
			wear.pressed.connect(_on_wear.bind(str(entry["uid"])))
			row.add_child(wear)
		_bag_box.add_child(row)

	_clear(_worn_box)
	var worn: Dictionary = Session.character.get("equipment", {})
	if worn.is_empty():
		_worn_box.add_child(_small_heading("(nothing)"))
	for slot in Equipment.slots():
		if not worn.has(slot):
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s: %s" % [str(slot), ItemDB.display_name(str(worn[slot].get("item_id", "")))]
		row.add_child(label)
		var take_off := Button.new()
		take_off.text = "Take off"
		take_off.pressed.connect(_on_take_off.bind(str(slot)))
		row.add_child(take_off)
		_worn_box.add_child(row)


func _refresh_stats() -> void:
	_clear(_stats_grid)
	for header in ["Stat", "Base", "Gear", "Final"]:
		var label: Label = Label.new()
		label.text = header
		label.add_theme_color_override("font_color", TSMTheme.ACCENT)
		_stats_grid.add_child(label)
	
	var result: Dictionary
	if Session.has_method("total_stats"):
		result = Session.total_stats(_mount_check.button_pressed) as Dictionary
	else:
		var class_id: String = str(Session.character.get("class_id", ""))
		var attrs: Dictionary = Session.character.get("attributes", {})
		var base: Dictionary = StatCalculator.attribute_totals(class_id, attrs)
		result = {
			"ok": true,
			"stats": base,
			"base_stats": base,
			"equipment_bonus": {}
		} as Dictionary
		
	if not bool(result.get("ok", false)):
		_say(str(result.get("message", "Could not calculate stats.")), true)
		return
		
	var stats_dict: Dictionary = result.get("stats", {})
	var base_dict: Dictionary = result.get("base_stats", {})
	var bonus_dict: Dictionary = result.get("equipment_bonus", {})
	
	for stat in stats_ict_keys_safe(stats_dict):
		var stat_name: String = str(stat)
		var bonus: float = float(bonus_dict.get(stat_name, 0.0))
		var cells: Array = [
			stat_name,
			_number(base_dict.get(stat_name, 0)),
			("+" + _number(bonus)) if bonus > 0.0 else (_number(bonus) if bonus < 0.0 else "-"),
			_number(stats_dict.get(stat_name, 0)),
		]
		for i in range(cells.size()):
			var cell_label: Label = Label.new()
			cell_label.text = str(cells[i])
			if i == 2 and bonus != 0.0:
				cell_label.add_theme_color_override("font_color", TSMTheme.OK)
			elif i == 0:
				cell_label.add_theme_color_override("font_color", TSMTheme.MUTED)
			_stats_grid.add_child(cell_label)

func stats_ict_keys_safe(d: Dictionary) -> Array:
	return d.keys()


func _number(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if is_equal_approx(number, round(number)) else "%.2f" % number


func _say(text: String, is_error: bool = false) -> void:
	_status.add_theme_color_override("font_color", TSMTheme.ERROR if is_error else TSMTheme.MUTED)
	_status.text = text


func _show(result: Dictionary, success_text: String) -> void:
	if result["ok"]:
		_say(success_text)
	else:
		_say(str(result.get("message", result.get("error", "Failed."))), true)


# ---------- buttons ----------

func _on_spend(attribute: String, amount: int) -> void:
	var alloc_res: Dictionary
	if Session.has_method("allocate_attribute"):
		alloc_res = await Session.allocate_attribute(attribute, amount) as Dictionary
	else:
		# Fallback: modify session character data directly if Session lacks the helper
		var c: Dictionary = Session.character
		var points: int = int(c.get("stat_points", 0))
		if points < amount:
			alloc_res = {"ok": false, "message": "Not enough attribute points."}
		else:
			c["stat_points"] = points - amount
			var attrs: Dictionary = c.get("attributes", {})
			attrs[attribute] = int(attrs.get(attribute, 0)) + amount
			c["attributes"] = attrs
			if Session.has_method("save_character") and Session.get("save_enabled"):
				await Session.save_character()
			if Session.has_signal("character_changed"):
				Session.emit_signal("character_changed")
			else:
				_refresh()
			alloc_res = {"ok": true}
	_show(alloc_res, "Spent %d point(s) on %s." % [amount, attribute.to_upper()])


func _on_exp(amount: int) -> void:
	var result: Dictionary
	if Session.has_method("grant_exp"):
		result = await Session.grant_exp(amount) as Dictionary
	else:
		# Fallback: handle EXP and level-ups directly in the dev screen if Session lacks the method
		var c: Dictionary = Session.character
		var current_exp: int = int(c.get("exp", 0)) + amount
		var level: int = int(c.get("level", 1))
		var levels_gained: int = 0
		
		# Simple level-up loop (e.g., 1000 exp per level for testing)
		var exp_per_level: int = 1000
		while current_exp >= exp_per_level:
			current_exp -= exp_per_level
			level += 1
			levels_gained += 1
			var points: int = int(c.get("stat_points", 0)) + 5 # 5 points per level up
			c["stat_points"] = points
			
		c["exp"] = current_exp
		c["level"] = level
		
		if Session.has_method("save_character"):
			await Session.save_character()
		if Session.has_signal("character_changed"):
			Session.emit_signal("character_changed")
		else:
			_refresh()
			
		result = {"ok": true, "levels_gained": levels_gained}
		
	_show(result, "Gained %d EXP (%d level(s))." % [amount, int(result.get("levels_gained", 0))])


func _on_add_selected() -> void:
	if _item_picker.selected < 0:
		return
	var item_id: String = _picker_ids[_item_picker.selected]
	var add_res: Dictionary
	if Session.has_method("add_item"):
		add_res = await Session.add_item(item_id, 1) as Dictionary
	else:
		# Fallback: add item directly to local inventory if Session lacks add_item
		var c: Dictionary = Session.character
		var inv: Array = c.get("inventory", [])
		inv.append({"item_id": item_id, "qty": 1})
		c["inventory"] = inv
		if Session.has_method("save_character"):
			await Session.save_character()
		if Session.has_signal("character_changed"):
			Session.emit_signal("character_changed")
		else:
			_refresh()
		add_res = {"ok": true}
	_show(add_res, "Added %s." % ItemDB.display_name(item_id))


func _on_add_all_gear() -> void:
	var added: int = 0
	for item_id_variant in DataRegistry.get_ids("items"):
		var item_id: String = str(item_id_variant)
		if ItemDB.equip_slot(item_id) == "":
			continue
		var result: Dictionary
		if Session.has_method("add_item"):
			result = await Session.add_item(item_id, 1) as Dictionary
		else:
			var c: Dictionary = Session.character
			var inv: Array = c.get("inventory", [])
			inv.append({"item_id": item_id, "qty": 1, "uid": "dev_" + str(randi())})
			c["inventory"] = inv
			result = {"ok": true}
			
		if not bool(result.get("ok", false)):
			_say(str(result.get("message", "Failed.")), true)
			return
		added += 1
		
	if Session.has_method("save_character"):
		await Session.save_character()
	if Session.has_signal("character_changed"):
		Session.emit_signal("character_changed")
	else:
		_refresh()
		
	_say("Added %d pieces of gear." % added)


func _on_wear(uid: String) -> void:
	var wear_res: Dictionary
	if Session.has_method("equip_item"):
		wear_res = await Session.equip_item(uid) as Dictionary
	else:
		# Fallback: equip item directly in session data
		var c: Dictionary = Session.character
		var inv: Array = c.get("inventory", [])
		var worn: Dictionary = c.get("equipment", {})
		var target_entry: Dictionary = {}
		var target_index: int = -1
		
		for i in range(inv.size()):
			var entry: Dictionary = inv[i] as Dictionary
			if str(entry.get("uid", "")) == uid:
				target_entry = entry
				target_index = i
				break
				
		if target_index == -1:
			wear_res = {"ok": false, "message": "Item not found in inventory."}
		else:
			var item_id: String = str(target_entry.get("item_id", ""))
			var slot: String = ItemDB.equip_slot(item_id)
			if slot == "":
				wear_res = {"ok": false, "message": "Item is not equipment."}
			else:
				# Unequip current item in slot back to bag if exists
				if worn.has(slot):
					inv.append(worn[slot])
				worn[slot] = target_entry
				inv.remove_at(target_index)
				c["inventory"] = inv
				c["equipment"] = worn
				
				if Session.has_method("save_character"):
					await Session.save_character()
				if Session.has_signal("character_changed"):
					Session.emit_signal("character_changed")
				else:
					_refresh()
				wear_res = {"ok": true}
				
	_show(wear_res, "Worn.")


func _on_take_off(slot: String) -> void:
	var take_off_res: Dictionary
	if Session.has_method("unequip_item"):
		take_off_res = await Session.unequip_item(slot) as Dictionary
	else:
		# Fallback: unequip item directly from slot back to inventory
		var c: Dictionary = Session.character
		var worn: Dictionary = c.get("equipment", {})
		if not worn.has(slot):
			take_off_res = {"ok": false, "message": "Nothing equipped in slot."}
		else:
			var inv: Array = c.get("inventory", [])
			inv.append(worn[slot])
			worn.erase(slot)
			c["inventory"] = inv
			c["equipment"] = worn
			
			if Session.has_method("save_character"):
				await Session.save_character()
			if Session.has_signal("character_changed"):
				Session.emit_signal("character_changed")
			else:
				_refresh()
			take_off_res = {"ok": true}
			
	_show(take_off_res, "Taken off.")
