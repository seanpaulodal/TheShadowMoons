class_name InventoryWindow
extends GameWindow
## The bag: tabs, search, sort, a grid of slots coloured by rarity, and a details
## panel with Equip / Use / Drop. It only shows and asks: every change goes
## through Session and the player.

const SLOT_SIZE := 100.0
const COLUMNS := 6

var _player: PlayerController
var _category: String = "all"
var _search: String = ""
var _sort_index: int = 0
var _selected_uid: String = ""
var _selected_item: String = ""

var _category_buttons: Dictionary = {}
var _search_edit: LineEdit
var _sort_button: Button
var _grid: GridContainer
var _capacity_label: Label
var _gold_label: Label
var _details: VBoxContainer
var _message: Label
var _equip_button: Button
var _use_button: Button
var _drop_button: Button


func setup(player: PlayerController) -> void:
	_player = player
	build("BAG")
	_build_layout()
	Session.character_changed.connect(func() -> void:
		if visible:
			refresh())


# ---------- layout ----------

func _build_layout() -> void:
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	left.add_child(tabs)
	var group := ButtonGroup.new()
	for category in InventoryView.CATEGORY_IDS:
		var tab := Button.new()
		tab.text = str(InventoryView.CATEGORY_NAMES[category])
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 56)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 19)
		tab.pressed.connect(_on_category.bind(str(category)))
		tabs.add_child(tab)
		_category_buttons[category] = tab
	(_category_buttons["all"] as Button).button_pressed = true

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	left.add_child(tools)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search items..."
	_search_edit.custom_minimum_size = Vector2(0, 56)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(_on_search)
	tools.add_child(_search_edit)
	_sort_button = Button.new()
	_sort_button.custom_minimum_size = Vector2(190, 56)
	_sort_button.text = str(InventoryView.SORT_NAMES[InventoryView.SORT_MODES[0]])
	_sort_button.pressed.connect(_on_sort)
	tools.add_child(_sort_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	var footer := HBoxContainer.new()
	left.add_child(footer)
	_capacity_label = Label.new()
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_capacity_label)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	footer.add_child(_gold_label)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(500, 0)
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

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 18)
	right_box.add_child(_message)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	right_box.add_child(actions)
	_equip_button = _action_button("Equip", _on_equip)
	_use_button = _action_button("Use", _on_use)
	_drop_button = _action_button("Drop", _on_drop)
	actions.add_child(_equip_button)
	actions.add_child(_use_button)
	actions.add_child(_drop_button)


func _action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 68)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(callback)
	return button


# ---------- drawing ----------

func refresh() -> void:
	if _grid == null or not Session.has_character():
		return
	var bag: Array = Session.character.get("inventory", [])
	_keep_selection_valid(bag)

	clear_children(_grid)
	var shown := InventoryView.filter(bag, _category, _search)
	for item in shown:
		_grid.add_child(_make_slot(item["entry"]))
	# With no filter, show the empty slots too, so the size of the bag can be seen.
	if _category == "all" and _search.strip_edges() == "":
		for i in range(bag.size(), Inventory.max_slots()):
			var empty := Panel.new()
			empty.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			empty.add_theme_stylebox_override("panel", slot_style(Color("2c2438"), false, false))
			_grid.add_child(empty)

	_capacity_label.text = "Bag  %d / %d" % [bag.size(), Inventory.max_slots()]
	_gold_label.text = "Gold  %s" % StatDisplay.format_number(int(Session.character.get("gold", 0)))
	_refresh_details()


func _make_slot(entry: Dictionary) -> Button:
	var item_id := str(entry.get("item_id", ""))
	var color := TSMTheme.rarity_color(ItemDB.rarity(item_id))
	var selected := _is_selected(entry)

	var button := Button.new()
	button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, slot_style(color, selected))
	button.pressed.connect(_on_slot_pressed.bind(entry))

	var icon_path := ItemDB.icon_path(item_id)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
	else:
		var initials := Label.new()
		initials.text = _initials(item_id)
		initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.add_theme_font_size_override("font_size", 30)
		initials.add_theme_color_override("font_color", color)
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(initials)

	if int(entry.get("qty", 1)) > 1:
		var badge := Label.new()
		badge.text = "x%d" % int(entry["qty"])
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
		badge.add_theme_font_size_override("font_size", 20)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
	return button


func _initials(item_id: String) -> String:
	var letters := ""
	for word in ItemDB.display_name(item_id).split(" ", false):
		letters += word.substr(0, 1).to_upper()
		if letters.length() >= 2:
			break
	return letters


func _refresh_details() -> void:
	clear_children(_details)
	var has_selection := _selected_item != ""
	_equip_button.visible = false
	_use_button.visible = false
	_drop_button.visible = has_selection
	if not has_selection:
		var hint := Label.new()
		hint.text = "Tap an item to see what it does."
		hint.add_theme_color_override("font_color", TSMTheme.MUTED)
		_details.add_child(hint)
		return
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	_details.add_child(holder)
	fill_item_lines(holder, _selected_item)
	_equip_button.visible = ItemDB.equip_slot(_selected_item) != ""
	_use_button.visible = not ItemDB.consumable_effect(_selected_item).is_empty()


# ---------- selection ----------

func _is_selected(entry: Dictionary) -> bool:
	if _selected_item == "":
		return false
	if _selected_uid != "":
		return str(entry.get("uid", "")) == _selected_uid
	return str(entry.get("item_id", "")) == _selected_item and not entry.has("uid")


func _keep_selection_valid(bag: Array) -> void:
	if _selected_item == "":
		return
	for entry in bag:
		if _is_selected(entry):
			return
	_selected_uid = ""
	_selected_item = ""


func select(entry: Dictionary) -> void:
	_selected_uid = str(entry.get("uid", ""))
	_selected_item = str(entry.get("item_id", ""))
	_message.text = ""
	refresh()


# ---------- buttons ----------

func _on_slot_pressed(entry: Dictionary) -> void:
	select(entry)


func _on_category(category: String) -> void:
	_category = category
	refresh()


func _on_search(text: String) -> void:
	_search = text
	refresh()


func _on_sort() -> void:
	var mode: String = InventoryView.SORT_MODES[_sort_index]
	Session.sort_inventory(mode)
	_sort_button.text = str(InventoryView.SORT_NAMES[mode])
	_sort_index = (_sort_index + 1) % InventoryView.SORT_MODES.size()


func _on_equip() -> void:
	if _selected_uid == "":
		return
	var result: Dictionary = Session.equip_item(_selected_uid)
	_message.text = "Equipped." if result["ok"] else str(result.get("message", "Could not equip."))
	_message.add_theme_color_override("font_color", TSMTheme.OK if result["ok"] else TSMTheme.ERROR)

func _on_use() -> void:
	if _selected_item == "":
		return
	var result: Dictionary = _player.use_consumable(_selected_item)
	if result["ok"]:
		_message.text = "Restored %d." % int(result["amount"])
		_message.add_theme_color_override("font_color", TSMTheme.OK)
	else:
		_message.text = str(result.get("message", "Could not use that."))
		_message.add_theme_color_override("font_color", TSMTheme.ERROR)


## Puts the selected item on the ground at the player's feet. Gear goes as a whole
## piece; for a stack, one item at a time.
func _on_drop() -> void:
	if _selected_item == "":
		return
	var item_id := _selected_item
	var result: Dictionary
	if _selected_uid != "":
		result = Session.remove_uid(_selected_uid)
	else:
		result = Session.remove_item(item_id, 1)
	if not result["ok"]:
		_message.text = str(result.get("message", "Could not drop that."))
		_message.add_theme_color_override("font_color", TSMTheme.ERROR)
		return
	LootDrop.spawn(_player.get_parent(), _player.global_position + Vector3(0, 0, -1.2), item_id, 1, 0, 1, 2.0)
	_message.text = "Dropped."
	_message.add_theme_color_override("font_color", TSMTheme.MUTED)
