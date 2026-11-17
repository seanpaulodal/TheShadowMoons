class_name ShopWindow
extends GameWindow
## A shop: a Buy tab (what the shop sells) and a Sell tab (your bag). Selling is
## only possible here. It shows and asks; the money and the bag change through
## Session. It stays open until it is closed with the X (or you die).

var _shop_id: String = ""
var _mode: String = "buy"
var _search: String = ""
var _selected_item: String = ""
var _selected_uid: String = ""
var _quantity: int = 1

var _tab_buttons: Dictionary = {}
var _search_edit: LineEdit
var _list: VBoxContainer
var _details: VBoxContainer
var _quantity_row: HBoxContainer
var _quantity_label: Label
var _total_label: Label
var _action_row: HBoxContainer
var _main_button: Button
var _all_button: Button
var _message: Label
var _gold_label: Label


func setup() -> void:
	build("SHOP")
	_build_layout()
	Session.character_changed.connect(func() -> void:
		if visible:
			refresh())


## Opens the shop with this id (see TSM_Shop_Rules.json) on the Buy tab.
func open_shop(shop_id: String) -> void:
	_shop_id = shop_id
	_title_label.text = str(Shop.shop_def(shop_id).get("name", "SHOP")).to_upper()
	_mode = "buy"
	_search = ""
	_search_edit.text = ""
	_selected_item = ""
	_selected_uid = ""
	_quantity = 1
	_message.text = ""
	(_tab_buttons["buy"] as Button).button_pressed = true
	open()


func shop_id() -> String:
	return _shop_id


# ---------- layout ----------

func _build_layout() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for entry in [["buy", "Buy"], ["sell", "Sell"]]:
		var tab := Button.new()
		tab.text = entry[1]
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(200, 60)
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(_on_tab.bind(str(entry[0])))
		tabs.add_child(tab)
		_tab_buttons[entry[0]] = tab
	(_tab_buttons["buy"] as Button).button_pressed = true

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search..."
	_search_edit.custom_minimum_size = Vector2(0, 56)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(_on_search)
	tabs.add_child(_search_edit)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)

	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
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

	_quantity_row = HBoxContainer.new()
	_quantity_row.add_theme_constant_override("separation", 6)
	right_box.add_child(_quantity_row)
	for entry in [["-10", -10], ["-", -1]]:
		_quantity_row.add_child(_step_button(str(entry[0]), int(entry[1])))
	_quantity_label = Label.new()
	_quantity_label.custom_minimum_size = Vector2(80, 0)
	_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity_label.add_theme_font_size_override("font_size", 26)
	_quantity_row.add_child(_quantity_label)
	for entry in [["+", 1], ["+10", 10]]:
		_quantity_row.add_child(_step_button(str(entry[0]), int(entry[1])))

	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", 22)
	_total_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	right_box.add_child(_total_label)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 18)
	right_box.add_child(_message)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	right_box.add_child(_action_row)
	_main_button = Button.new()
	_main_button.custom_minimum_size = Vector2(0, 72)
	_main_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_button.add_theme_font_size_override("font_size", 26)
	_main_button.pressed.connect(_on_main)
	_action_row.add_child(_main_button)
	_all_button = Button.new()
	_all_button.text = "Sell all"
	_all_button.custom_minimum_size = Vector2(0, 72)
	_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_all_button.add_theme_font_size_override("font_size", 26)
	_all_button.pressed.connect(_on_sell_all)
	_action_row.add_child(_all_button)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 22)
	_gold_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	body.add_child(_gold_label)


func _step_button(text: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(90, 60)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(_on_step.bind(step))
	return button


# ---------- drawing ----------

func refresh() -> void:
	if _list == null or not Session.has_character():
		return
	_gold_label.text = "Gold  %s" % StatDisplay.format_number(int(Session.character.get("gold", 0)))
	clear_children(_list)
	if _mode == "buy":
		_refresh_buy_list()
	else:
		_refresh_sell_list()
	_refresh_details()


func _refresh_buy_list() -> void:
	var needle := _search.strip_edges().to_lower()
	for item_id in Shop.stock(_shop_id):
		if needle != "" and not ItemDB.display_name(item_id).to_lower().contains(needle):
			continue
		_list.add_child(_row(item_id, "", Shop.buy_price(item_id), item_id == _selected_item))


func _refresh_sell_list() -> void:
	var bag: Array = Session.character.get("inventory", [])
	var needle := _search.strip_edges().to_lower()
	var any := false
	for entry in bag:
		var item_id := str(entry.get("item_id", ""))
		if Shop.sell_price(item_id) <= 0:
			continue
		if needle != "" and not ItemDB.display_name(item_id).to_lower().contains(needle):
			continue
		var selected := _selected_item == item_id and str(entry.get("uid", "")) == _selected_uid
		var suffix := "  x%d" % int(entry["qty"]) if int(entry.get("qty", 1)) > 1 else ""
		var row := _row(item_id, suffix, Shop.sell_price(item_id), selected)
		row.pressed.connect(_on_select_sell.bind(entry))
		_list.add_child(row)
		any = true
	if not any:
		var empty := Label.new()
		empty.text = "Nothing to sell."
		empty.add_theme_color_override("font_color", TSMTheme.MUTED)
		_list.add_child(empty)


func _row(item_id: String, suffix: String, price: int, selected: bool) -> Button:
	var button := Button.new()
	button.text = "%s%s      %s g" % [ItemDB.display_name(item_id), suffix, StatDisplay.format_number(price)]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 64)
	button.add_theme_font_size_override("font_size", 22)
	var color := TSMTheme.rarity_color(ItemDB.rarity(item_id))
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	if selected:
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, slot_style(TSMTheme.ACCENT, true))
	if _mode == "buy":
		button.pressed.connect(select_buy.bind(item_id))
	return button


func _refresh_details() -> void:
	clear_children(_details)
	var has_selection := _selected_item != ""
	_quantity_row.visible = has_selection and _quantity_allowed()
	_total_label.visible = has_selection
	_main_button.visible = has_selection
	_all_button.visible = has_selection and _mode == "sell" and _selected_uid == "" and _owned() > 1
	if not has_selection:
		var hint := Label.new()
		hint.text = "Tap an item to see it." if _mode == "buy" else "Tap one of your items to sell it."
		hint.add_theme_color_override("font_color", TSMTheme.MUTED)
		_details.add_child(hint)
		return

	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	_details.add_child(holder)
	fill_item_lines(holder, _selected_item)

	_quantity = clampi(_quantity, 1, maxi(1, _max_quantity()))
	_quantity_label.text = str(_quantity)
	if _mode == "buy":
		var cost := Shop.buy_price(_selected_item) * _quantity
		_total_label.text = "Total  %s g" % StatDisplay.format_number(cost)
		_main_button.text = "Buy"
		_main_button.disabled = cost > int(Session.character.get("gold", 0))
	else:
		_total_label.text = "You get  %s g" % StatDisplay.format_number(Shop.sell_price(_selected_item) * _quantity)
		_main_button.text = "Sell"
		_main_button.disabled = false


func _quantity_allowed() -> bool:
	return ItemDB.is_stackable(_selected_item) and (_mode == "buy" or _owned() > 1)


func _max_quantity() -> int:
	if not _quantity_allowed():
		return 1
	return 99 if _mode == "buy" else _owned()


func _owned() -> int:
	return Inventory.count(Session.character.get("inventory", []), _selected_item)


# ---------- selection and buttons ----------

func select_buy(item_id: String) -> void:
	_selected_item = item_id
	_selected_uid = ""
	_quantity = 1
	_message.text = ""
	refresh()


func _on_select_sell(entry: Dictionary) -> void:
	select_sell(entry)


func select_sell(entry: Dictionary) -> void:
	_selected_item = str(entry.get("item_id", ""))
	_selected_uid = str(entry.get("uid", ""))
	_quantity = 1
	_message.text = ""
	refresh()


func _on_search(text: String) -> void:
	_search = text
	refresh()


func _on_tab(mode: String) -> void:
	_mode = mode
	_selected_item = ""
	_selected_uid = ""
	_quantity = 1
	_message.text = ""
	refresh()


func _on_step(step: int) -> void:
	_quantity = clampi(_quantity + step, 1, maxi(1, _max_quantity()))
	_refresh_details()


func _on_main() -> void:
	if _selected_item == "":
		return
	if _mode == "buy":
		_report(Session.buy_item(_selected_item, _quantity), "Bought %s x%d." % [ItemDB.display_name(_selected_item), _quantity])
	else:
		_report(Session.sell_item(_selected_item, _quantity, _selected_uid), "Sold %s." % ItemDB.display_name(_selected_item))


func _on_sell_all() -> void:
	if _selected_item == "":
		return
	_report(Session.sell_item(_selected_item, _owned(), ""), "Sold all %s." % ItemDB.display_name(_selected_item))


func _report(result: Dictionary, success_text: String) -> void:
	if result["ok"]:
		_message.text = success_text
		_message.add_theme_color_override("font_color", TSMTheme.OK)
	else:
		_message.text = str(result.get("message", "That did not work."))
		_message.add_theme_color_override("font_color", TSMTheme.ERROR)
