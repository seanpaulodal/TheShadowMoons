extends Node
## DEV ONLY. Checks the HUD, the bag window and the character window (M7), and
## the logic behind them: stat and item text, sorting and filtering, using
## potions, dropping items. Needs no login and saves nothing. Run with F6.

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _hud: CombatHud


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character()

	_test_stat_display()
	_test_item_info()
	_test_inventory_view()
	await _build_arena()
	_test_restore_and_potions()
	await _test_drop_and_sort_logic()
	await _test_hud()
	await _test_inventory_window()
	await _test_character_window()

	Session.save_enabled = true
	Session.clear()
	print("[ui] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[ui] PASS  ", label)
	else:
		_failed += 1
		print("[ui] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_character() -> void:
	Session.character = {
		"name": "Fighter", "class_id": "warrior", "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _line_texts(item_id: String) -> Array:
	var texts: Array = []
	for line in ItemInfo.lines(item_id):
		texts.append(str(line["text"]))
	return texts


func _bag_of(ids: Array) -> Array:
	var bag: Array = []
	for item_id in ids:
		bag = Inventory.add(bag, item_id, 1)["inventory"]
	return bag


func _build_arena() -> void:
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	_hud = _world.combat_hud
	for camp in _world.camps:
		camp.queue_free()
	for child in _world.get_children():
		if child is TrainingDummy:
			child.queue_free()
	for node in get_tree().get_nodes_in_group("targetable"):
		node.queue_free()
	await _frames(3)


# ---------- text and numbers ----------

func _test_stat_display() -> void:
	print("[ui] --- stat text ---")
	_eq("a percent stat", StatDisplay.format_stat("crit_chance", 5.8), "5.8%")
	_eq("a whole percent", StatDisplay.format_stat("crit_damage", 151.0), "151%")
	_eq("attack speed", StatDisplay.format_stat("atk_speed", 1.028), "1.03x")
	_eq("move speed", StatDisplay.format_stat("move_speed", 7.06), "7.06")
	_eq("a big number gets commas", StatDisplay.format_stat("max_health", 1234567), "1,234,567")
	_eq("attack range", StatDisplay.format_stat("attack_range", 3.0), "3")
	_eq("a flat bonus", StatDisplay.format_bonus("atk_power", 15.0), "+15")
	_eq("a percent bonus", StatDisplay.format_bonus("crit_chance", 5.0), "+5%")
	_eq("a negative bonus", StatDisplay.format_bonus("atk_speed", -0.1), "-0.10x")
	_eq("numbers: 0", StatDisplay.format_number(0), "0")
	_eq("numbers: 999", StatDisplay.format_number(999), "999")
	_eq("numbers: 1000", StatDisplay.format_number(1000), "1,000")
	_eq("numbers: 1234567", StatDisplay.format_number(1234567), "1,234,567")
	_eq("numbers: negative", StatDisplay.format_number(-1500), "-1,500")
	_eq("EXP text with 4 decimals", StatDisplay.exp_text(27, 64800), "Level 27 (EXP 88.8889%)")
	_eq("EXP text at the start", StatDisplay.exp_text(1, 0), "Level 1 (EXP 0.0000%)")
	_eq("EXP text at the maximum level", StatDisplay.exp_text(300, 0), "Level 300 (MAX)")
	_eq("EXP fraction", StatDisplay.exp_fraction(1, 50), 0.5)
	_eq("a stat has a readable name", StatDisplay.stat_name("def_power"), "Defense")
	_eq("an unknown stat still gets a name", StatDisplay.stat_name("some_new_stat"), "Some New Stat")

	var grouped: Array = []
	for group in StatDisplay.GROUPS:
		grouped.append_array(group[1])
	var missing: Array = []
	for stat in DataRegistry.get_config("stat_rules")["stats"]:
		if not grouped.has(stat):
			missing.append(stat)
	_eq("every stat in the rules is shown in the stat table", missing, [])


func _test_item_info() -> void:
	print("[ui] --- item text ---")
	var sword := _line_texts("wooden_sword")
	_eq("sword: damage range", sword.has("Damage  10 - 18"), true)
	_eq("sword: attack bonus", sword.has("Attack  +15"), true)
	_eq("sword: crit chance bonus", sword.has("Crit Chance  +5%"), true)
	_eq("sword: crit damage bonus", sword.has("Crit Damage  +25%"), true)
	_eq("sword: first line says weapon and rarity", str(sword[0]).begins_with("Weapon  -  Weapon"), true)
	var has_price := false
	for line in ItemInfo.lines("wooden_sword"):
		if line["kind"] == "price":
			has_price = true
	_eq("sword: has a price line", has_price, true)

	var flame := _line_texts("flame_blade")
	_eq("flame blade: fire damage", flame.has("Fire damage  +25"), true)
	_eq("flame blade: burn chance", flame.has("25% chance to inflict Burn"), true)
	_eq("healing potion", _line_texts("healing_potion").has("Restores 25 HP"), true)
	_eq("mana potion", _line_texts("potion_mp_minor").any(func(t: String) -> bool: return t.begins_with("Restores") and t.ends_with("MP")), true)
	_eq("stamina potion", _line_texts("potion_sp_minor").any(func(t: String) -> bool: return t.begins_with("Restores") and t.ends_with("SP")), true)
	_eq("a mount says it only works while riding", _line_texts("shadow_steed_mount").any(func(t: String) -> bool: return "(while riding)" in t), true)
	_eq("a ring says Ring", str(_line_texts("iron_ring")[0]).contains("Ring"), true)
	_eq("an unknown item is handled", ItemInfo.lines("not_an_item")[0]["text"], "Unknown item")
	_eq("slot names", [ItemInfo.slot_label("ring_2"), ItemInfo.slot_label("pants")], ["Ring", "Pants"])


func _test_inventory_view() -> void:
	print("[ui] --- bag filtering and sorting ---")
	_eq("sword is under weapons", InventoryView.category_of("wooden_sword"), "weapons")
	_eq("armor is under armor", InventoryView.category_of("iron_armor"), "armor")
	_eq("a ring is under accessories", InventoryView.category_of("iron_ring"), "accessories")
	_eq("a potion is under potions", InventoryView.category_of("healing_potion"), "consumables")
	_eq("a mount is under other", InventoryView.category_of("shadow_steed_mount"), "other")

	var bag := _bag_of(["iron_sword", "healing_potion", "wooden_sword", "iron_ring", "shadow_steed_mount", "iron_armor"])
	_eq("all shows everything", InventoryView.filter(bag, "all", "").size(), 6)
	_eq("weapons shows the two swords", InventoryView.filter(bag, "weapons", "").size(), 2)
	_eq("potions shows one", InventoryView.filter(bag, "consumables", "").size(), 1)
	_eq("search finds both swords", InventoryView.filter(bag, "all", "sword").size(), 2)
	_eq("search ignores capital letters", InventoryView.filter(bag, "all", "SWORD").size(), 2)
	_eq("search inside a tab", InventoryView.filter(bag, "armor", "sword").size(), 0)
	_eq("a search with nothing found", InventoryView.filter(bag, "all", "dragon").size(), 0)
	_eq("the result remembers where each item sits in the bag", InventoryView.filter(bag, "armor", "")[0]["index"], 5)

	var by_name := InventoryView.sorted(bag, "name")
	var names: Array = []
	for entry in by_name:
		names.append(ItemDB.display_name(entry["item_id"]).to_lower())
	var ordered := names.duplicate()
	ordered.sort()
	_eq("sort by name puts them in alphabetical order", names, ordered)

	var by_rarity := InventoryView.sorted(bag, "rarity")
	var ranks: Array = []
	for entry in by_rarity:
		ranks.append(InventoryView.RARITY_ORDER.find(ItemDB.rarity(entry["item_id"]).to_lower()))
	var rank_ok := true
	for i in range(1, ranks.size()):
		if ranks[i] > ranks[i - 1]:
			rank_ok = false
	_eq("sort by rarity puts the best first", rank_ok, true)

	var by_type := InventoryView.sorted(bag, "type")
	var type_ranks: Array = []
	for entry in by_type:
		type_ranks.append(InventoryView.CATEGORY_IDS.find(InventoryView.category_of(entry["item_id"])))
	var type_ok := true
	for i in range(1, type_ranks.size()):
		if type_ranks[i] < type_ranks[i - 1]:
			type_ok = false
	_eq("sort by type groups the tabs together", type_ok, true)
	_eq("sorting keeps every item", by_type.size(), bag.size())
	var uids := {}
	for entry in by_type:
		if entry.has("uid"):
			uids[entry["uid"]] = true
	_eq("...and every unique id", uids.size(), 5)
	_eq("the original bag is not changed", bag[0]["item_id"], "iron_sword")


# ---------- potions ----------

func _test_restore_and_potions() -> void:
	print("[ui] --- potions ---")
	var fighter := Combatant.new()
	fighter.setup("T", 1, {"max_health": 100, "max_mana": 50, "max_stamina": 40})
	fighter.take_damage(60)
	fighter.mp = 10
	fighter.sp = 5
	_eq("restore health", fighter.restore("health", 25), 25)
	_eq("...health went up", fighter.hp, 65)
	_eq("restore health beyond the maximum", fighter.restore("health", 500), 35)
	_eq("...stops at the maximum", fighter.hp, 100)
	_eq("restore mana", fighter.restore("mana", 100), 40)
	_eq("restore stamina", fighter.restore("stamina", 10), 10)
	_eq("nothing to restore when full", fighter.restore("health", 10), 0)
	_eq("an unknown resource restores nothing", fighter.restore("luck", 10), 0)

	_new_character()
	Session.add_item("healing_potion", 2)
	_player.combatant.take_damage(50)
	var hp_before := _player.combatant.hp
	var used := _player.use_consumable("healing_potion")
	_eq("using a health potion works", used["ok"], true)
	_eq("...it restores its 25", _player.combatant.hp, hp_before + 25)
	_eq("...and one is used up", Inventory.count(Session.character["inventory"], "healing_potion"), 1)
	_player.combatant.heal(1000)
	var full := _player.use_consumable("healing_potion")
	_eq("a full bar refuses the potion", full["error"], "ALREADY_FULL")
	_eq("...and keeps the potion", Inventory.count(Session.character["inventory"], "healing_potion"), 1)

	Session.add_item("potion_mp_minor", 1)
	_player.combatant.mp = 1
	_eq("a mana potion works", _player.use_consumable("potion_mp_minor")["ok"], true)
	_report("...and gives mana", _player.combatant.mp > 1)
	Session.add_item("potion_sp_minor", 1)
	_player.combatant.sp = 1
	_eq("a stamina potion works", _player.use_consumable("potion_sp_minor")["ok"], true)
	_eq("a sword can not be used", _player.use_consumable("iron_sword")["error"], "NOT_USABLE")
	_eq("an item you do not have", _player.use_consumable("potion_hp_royal")["error"], "NOT_FOUND")
	_player.combatant.take_damage(_player.combatant.hp)
	_eq("the dead can not use items", _player.use_consumable("healing_potion")["error"], "DEAD")
	_player.revive()
	await _frames(2)


func _test_drop_and_sort_logic() -> void:
	print("[ui] --- dropping and sorting ---")
	_new_character()
	_player.refresh_stats()
	Session.add_item("iron_sword", 1)
	Session.add_item("healing_potion", 2)
	var uid: String = Session.character["inventory"][0]["uid"]
	var removed := Session.remove_uid(uid)
	_eq("a piece of gear can be taken out by its id", removed["ok"], true)
	_eq("...and comes back as an entry", removed["entry"]["item_id"], "iron_sword")
	_eq("...it left the bag", Session.character["inventory"].size(), 1)
	_eq("removing an id that is not there", Session.remove_uid("nope")["error"], "NOT_FOUND")

	Session.add_item("wooden_sword", 1)
	Session.add_item("iron_ring", 1)
	var before: Array = Session.character["inventory"].duplicate(true)
	var sorted := Session.sort_inventory("name")
	_eq("sorting the bag works", sorted["ok"], true)
	_eq("...nothing lost", Session.character["inventory"].size(), before.size())
	_eq("...and it is waiting to be saved", Session.has_unsaved_changes(), true)

	# A dropped item waits before it can be picked up again.
	var drop := LootDrop.spawn(_world, _player.global_position, "iron_ring", 1, 0, 1, 1.5)
	await _frames(30)
	_eq("a fresh drop is not picked up at once", is_instance_valid(drop) and not drop.is_queued_for_deletion(), true)
	await _frames(90)
	_eq("...but is picked up after the delay", drop == null or not is_instance_valid(drop) or drop.is_queued_for_deletion(), true)
	_new_character()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await _frames(2)


# ---------- HUD ----------

func _test_hud() -> void:
	print("[ui] --- HUD ---")
	_new_character()
	_player.refresh_stats()
	Session.character_changed.emit()
	await _frames(3)
	_report("the player frame shows name, class and level", "Fighter" in _hud._name_label.text and "Warrior" in _hud._name_label.text and "Lv 1" in _hud._name_label.text, _hud._name_label.text)
	_eq("the EXP text matches the rules", _hud._exp_text.text, "Level 1 (EXP 0.0000%)")
	_eq("gold starts at 0", _hud._gold_label.text, "Gold  0")
	Session.grant_rewards(50, 1234)
	await _frames(3)
	_eq("gold has commas", _hud._gold_label.text, "Gold  1,234")
	_eq("the EXP text follows", _hud._exp_text.text, "Level 1 (EXP 50.0000%)")
	_near_bar("the EXP bar is half full", _hud._exp_bar.value, 0.5)
	_report("the HP text is filled in", "134 / 134" in _hud._hp_text.text, _hud._hp_text.text)

	_player.combatant.status.apply("Slow")
	await _frames(15)
	_eq("a status effect shows as a chip", _hud._buff_box.get_child_count(), 1)
	_report("...with its name and time", "Slow" in (_hud._buff_box.get_child(0).get_child(0) as Label).text, (_hud._buff_box.get_child(0).get_child(0) as Label).text)
	_player.combatant.status.apply("Poison")
	_player.combatant.status.apply("Poison")
	await _frames(15)
	_eq("two effects, two chips", _hud._buff_box.get_child_count(), 2)
	_report("stacks are shown", (_hud._buff_box.get_child(1).get_child(0) as Label).text.contains("x2"))
	_player.combatant.status.clear()
	await _frames(15)
	_eq("the chips go away with the effects", _hud._buff_box.get_child_count(), 0)

	# Windows and the touch controls.
	_eq("no window is open at the start", _hud.is_window_open(), false)
	_hud.open_inventory()
	_eq("the Bag button opens the bag", _hud.inventory_window.visible, true)
	_eq("...and switches the touch controls off", _world.controls.enabled, false)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(150, 700)
	_world.controls._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(260, 700)
	drag.relative = Vector2(110, 0)
	_world.controls._input(drag)
	_eq("taps on a window do not move the character", _world.controls.move_vector, Vector2.ZERO)
	_hud.open_character()
	_eq("opening the character window closes the bag", [_hud.inventory_window.visible, _hud.character_window.visible], [false, true])
	_eq("controls stay off while a window is open", _world.controls.enabled, false)
	_hud.close_windows()
	_eq("closing everything turns the controls back on", _world.controls.enabled, true)

	# Not fired here (it would really sign out and leave the scene); only the wiring is checked.
	_eq("the character window's Sign Out is connected to the HUD", _hud.character_window.sign_out_requested.get_connections().size(), 1)
	_eq("...and the HUD's to the world", _hud.sign_out_requested.get_connections().size() >= 1, true)


func _near_bar(label: String, got: float, expected: float) -> void:
	_report(label, absf(got - expected) < 0.001, "expected %s, got %s" % [str(expected), str(got)])


# ---------- bag window ----------

func _slot_buttons(window: InventoryWindow) -> Array:
	var buttons: Array = []
	for child in window._grid.get_children():
		if child is Button:
			buttons.append(child)
	return buttons


func _test_inventory_window() -> void:
	print("[ui] --- bag window ---")
	_new_character()
	_player.refresh_stats()
	Session.add_item("iron_sword", 2)
	Session.add_item("healing_potion", 3)
	Session.add_item("iron_ring", 1)
	Session.add_item("shadow_steed_mount", 1)
	var window := _hud.inventory_window
	_hud.open_inventory()
	await _frames(2)

	_eq("the grid shows the whole bag (60 slots)", window._grid.get_child_count(), 60)
	_eq("5 of the slots hold items (2 swords, potions, ring, mount)", _slot_buttons(window).size(), 5)
	_eq("the bag size is shown", window._capacity_label.text, "Bag  5 / 60")
	_report("the gold is shown", "Gold" in window._gold_label.text)
	_report("a slot is big enough to tap (100)", _slot_buttons(window)[0].custom_minimum_size.x >= 100.0)
	_report("a stack shows its amount", _slot_buttons(window).any(func(b: Button) -> bool:
		return b.get_children().any(func(c: Node) -> bool: return c is Label and (c as Label).text == "x3")))

	window._on_category("weapons")
	_eq("the Weapons tab shows only the swords", _slot_buttons(window).size(), 2)
	_eq("a filtered bag shows no empty slots", window._grid.get_child_count(), 2)
	window._on_category("consumables")
	_eq("the Potions tab shows the potion stack", _slot_buttons(window).size(), 1)
	window._on_category("all")
	window._on_search("ring")
	_eq("searching for 'ring' finds one item", _slot_buttons(window).size(), 1)
	window._on_search("")
	_eq("clearing the search brings everything back", _slot_buttons(window).size(), 5)

	_eq("nothing is selected at first", window._selected_item, "")
	_eq("...so Drop is hidden", window._drop_button.visible, false)
	var sword_entry: Dictionary = Session.character["inventory"][0]
	window.select(sword_entry)
	_eq("selecting a sword shows Equip", window._equip_button.visible, true)
	_eq("...hides Use", window._use_button.visible, false)
	_eq("...and shows Drop", window._drop_button.visible, true)
	_report("the details show its name", window._details.get_child(0).get_child(0) is Label and (window._details.get_child(0).get_child(0) as Label).text == "Iron Sword")
	window._on_equip()
	await _frames(2)
	_eq("Equip wears the sword", Session.character["equipment"]["weapon"]["item_id"], "iron_sword")
	_eq("...it left the bag grid", _slot_buttons(window).size(), 4)
	_eq("...and the selection is cleared", window._selected_item, "")
	_eq("the combat profile follows the new weapon", _player.combatant.attack_profile.has("min"), true)

	var potion_entry: Dictionary = {}
	for entry in Session.character["inventory"]:
		if entry["item_id"] == "healing_potion":
			potion_entry = entry
	window.select(potion_entry)
	_eq("a potion shows Use", window._use_button.visible, true)
	_eq("...but not Equip", window._equip_button.visible, false)
	window._on_use()
	_eq("Use on a full bar says so", window._message.text, "Already full.")
	_player.combatant.take_damage(60)
	var hp_before := _player.combatant.hp
	window._on_use()
	_eq("Use heals the player", _player.combatant.hp, hp_before + 25)
	_eq("...and uses up one potion", Inventory.count(Session.character["inventory"], "healing_potion"), 2)

	window._on_drop()
	await _frames(2)
	_eq("Drop takes one potion out of the bag", Inventory.count(Session.character["inventory"], "healing_potion"), 1)
	var dropped := get_tree().get_nodes_in_group("loot")
	_eq("...and puts it on the ground", dropped.size(), 1)
	_report("...with a delay before it can be picked up", (dropped[0] as LootDrop).pickup_delay > 0.0)
	for node in dropped:
		node.queue_free()

	window._on_sort()
	await _frames(2)
	var order: Array = []
	for entry in Session.character["inventory"]:
		order.append(InventoryView.CATEGORY_IDS.find(InventoryView.category_of(entry["item_id"])))
	var sorted_ok := true
	for i in range(1, order.size()):
		if order[i] < order[i - 1]:
			sorted_ok = false
	_eq("the Sort button puts the bag in type order", sorted_ok, true)
	_report("the Sort button shows which sort it used", "Type" in window._sort_button.text, window._sort_button.text)

	# A selected item that disappears is un-selected.
	window.select(Session.character["inventory"][0])
	Session.remove_item(str(Session.character["inventory"][0]["item_id"]), 1)
	await _frames(2)
	_report("removing the selected item clears the details", window._selected_item == "" or Inventory.count(Session.character["inventory"], window._selected_item) > 0)

	# A full bag.
	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	Session.character["inventory"] = full
	Session.character_changed.emit()
	await _frames(2)
	_eq("a full bag reads 60 / 60", window._capacity_label.text, "Bag  60 / 60")
	_hud.close_windows()


# ---------- character window ----------

func _test_character_window() -> void:
	print("[ui] --- character window ---")
	_new_character()
	_player.refresh_stats()
	var window := _hud.character_window
	_hud.open_character()
	await _frames(2)

	_report("the header names the character", "Fighter" in window._header.text and "Warrior" in window._header.text, window._header.text)
	_eq("EXP text uses 4 decimals", window._exp_label.text, "Level 1 (EXP 0.0000%)")
	_eq("all 8 attributes are listed", window._attribute_box.get_child_count(), 8)
	var first_plus := (window._attribute_box.get_child(0) as HBoxContainer).get_child(2) as Button
	_eq("with no points the + buttons are off", first_plus.disabled, true)
	_report("the stat table shows Attack", window._stats_grid.get_children().any(func(n: Node) -> bool:
		return n is HBoxContainer and (n.get_child(0) as Label).text == "Attack"))

	Session.grant_exp(100)
	await _frames(2)
	_eq("a level gives 5 points", window._points_label.text, "Stat points: 5")
	first_plus = (window._attribute_box.get_child(0) as HBoxContainer).get_child(2) as Button
	_eq("...and the + buttons turn on", first_plus.disabled, false)
	var str_before: int = int(StatCalculator.attribute_totals("warrior", Session.character["attributes"])["str"])
	window._on_spend("str", 1)
	await _frames(2)
	_eq("spending a point raises the attribute", int(StatCalculator.attribute_totals("warrior", Session.character["attributes"])["str"]), str_before + 1)
	_eq("...and uses the point", window._points_label.text, "Stat points: 4")
	var five := (window._attribute_box.get_child(0) as HBoxContainer).get_child(3) as Button
	_eq("+5 is off with only 4 points", five.disabled, true)

	# Gear shows up in the stat table.
	Session.add_item("wooden_sword", 1)
	var bag: Array = Session.character["inventory"]
	Session.equip_item(str(bag[bag.size() - 1]["uid"]))
	await _frames(2)
	var shows_bonus := false
	for row in window._stats_grid.get_children():
		if row is HBoxContainer and (row.get_child(0) as Label).text == "Attack" and row.get_child_count() == 3:
			shows_bonus = (row.get_child(1) as Label).text == "(+15)"
	_eq("a worn sword shows its +15 attack in green", shows_bonus, true)

	window._show_page("Equipment")
	await _frames(2)
	_eq("the Equipment tab lists all 11 slots", window._slot_box.get_child_count(), 11)
	var weapon_row := window._slot_box.get_child(0) as HBoxContainer
	_eq("the weapon slot shows the sword", (weapon_row.get_child(1) as Label).text, "Wooden Sword")
	_eq("...with Details and Take off", weapon_row.get_child_count(), 4)
	var helmet_row := window._slot_box.get_child(2) as HBoxContainer
	_eq("an empty slot says (empty)", (helmet_row.get_child(1) as Label).text, "(empty)")
	window._on_details("wooden_sword")
	_report("Details shows the item", window._slot_details.get_child_count() == 1)
	window._on_take_off("weapon")
	await _frames(2)
	_eq("Take off puts it back in the bag", Session.character["equipment"].has("weapon"), false)
	_eq("...the row is empty again", ((window._slot_box.get_child(0) as HBoxContainer).get_child(1) as Label).text, "(empty)")
	_hud.close_windows()
	_eq("the controls are back on", _world.controls.enabled, true)
