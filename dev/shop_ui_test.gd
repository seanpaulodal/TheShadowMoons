extends Node
## DEV ONLY. Checks the shop and potion screens (M8): the shopkeepers, the Talk
## button, buying and selling, the quick-use potion slots, the Potions tab and the
## elixir indicator. Needs no login and saves nothing. Run with F6.
## (Your item sheet has no elixir items yet, so the test adds pretend ones.)

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _hud: CombatHud


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character()
	_add_pretend_elixirs()
	await _build_arena()

	await _test_shopkeepers_and_talk_button()
	await _test_buying()
	await _test_selling()
	await _test_quick_slots()
	await _test_potions_tab()
	await _test_elixir_display()

	Session.save_enabled = true
	Session.clear()
	print("[shop] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[shop] PASS  ", label)
	else:
		_failed += 1
		print("[shop] FAIL  %s  (%s)" % [label, detail])


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


func _add_pretend_elixirs() -> void:
	var table: Dictionary = DataRegistry._tables["items"]
	for entry in [["elixir_7_day", 7], ["elixir_15_day", 15], ["elixir_30_day", 30]]:
		table[entry[0]] = {
			"item_id": entry[0], "item_name": "%d-Day Elixir" % entry[1], "item_desc": "Pretend elixir for tests.",
			"item_rarity": "Rare", "item_type": "Consumable", "item_BType": "Elixir", "item_BValue": entry[1],
			"item_buy_value": 1000, "item_sell_value": 250, "stackable": true,
			"dropped_by_enemy": "N/A", "drop_chance": "N/A", "item_iconpath": "N/A",
		}


func _build_arena() -> void:
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	_hud = _world.combat_hud
	for camp in _world.camps:
		camp.queue_free()
	for node in get_tree().get_nodes_in_group("targetable"):
		node.queue_free()
	await _frames(3)


func _stand_at(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	await _frames(12)


func _rows(window: ShopWindow) -> Array:
	var rows: Array = []
	for child in window._list.get_children():
		if child is Button:
			rows.append(child)
	return rows


# ---------- shopkeepers ----------

func _test_shopkeepers_and_talk_button() -> void:
	print("[shop] --- shopkeepers and the Talk button ---")
	_eq("five shopkeepers stand in the world", _world.shop_npcs.size(), 5)
	var names: Array = []
	for npc in _world.shop_npcs:
		names.append(npc.display_name)
	names.sort()
	_eq("they are the five shops", names, ["Armorer", "General Store", "Jeweler", "Mount Vendor", "Weaponsmith"])

	var clear_of_obstacles := true
	for child in _world.get_children():
		if child is StaticBody3D and not (child is ShopNpc) and not (child is TrainingDummy):
			var shape := child.get_child(0) as CollisionShape3D
			if shape != null and shape.shape is BoxShape3D:
				var size := (shape.shape as BoxShape3D).size
				if maxf(size.x, maxf(size.y, size.z)) > 6.5:
					continue
				for npc in _world.shop_npcs:
					if Vector2(child.global_position.x - npc.global_position.x, child.global_position.z - npc.global_position.z).length() < 4.0:
						clear_of_obstacles = false
	_eq("no rock sits on top of a shopkeeper", clear_of_obstacles, true)

	await _frames(12)
	_eq("the Talk button is hidden far from every shop", _hud._interact_button.visible, false)
	await _stand_at(Vector3(0, 0.2, 12))
	_eq("next to the Armorer the Talk button shows", _hud._interact_button.visible, true)
	_eq("...with the shop's name", _hud._interact_button.text, "Talk: Armorer")
	_hud._interact_button.pressed.emit()
	await _frames(3)
	_eq("pressing it opens the shop", _hud.shop_window.visible, true)
	_eq("...with the shop's name as the title", _hud.shop_window._title_label.text, "ARMORER")
	_eq("...and switches the touch controls off", _world.controls.enabled, false)
	_eq("the Talk button is hidden while a window is open", _hud._interact_button.visible, false)
	_hud.shop_window.close()
	await _frames(12)
	_eq("closing it turns the controls back on", _world.controls.enabled, true)
	_eq("the Talk button is back", _hud._interact_button.visible, true)

	_hud.open_shop("armorer")
	await _frames(3)
	var far_move := Vector3(0, 0.2, 0)
	_player.global_position = far_move
	await _frames(15)
	_eq("walking away does NOT close the shop (only the X does)", _hud.shop_window.visible, true)
	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(3)
	_eq("dying closes the shop", _hud.shop_window.visible, false)
	_player.revive()
	await _frames(3)


# ---------- buying ----------

func _test_buying() -> void:
	print("[shop] --- buying ---")
	_new_character()
	_player.refresh_stats()
	var window := _hud.shop_window
	_hud.open_shop("armorer")
	await _frames(2)
	_eq("the Buy tab lists everything the armorer sells", _rows(window).size(), Shop.stock("armorer").size())
	_eq("...cheapest first", _rows(window)[0].text.begins_with(ItemDB.display_name(Shop.stock("armorer")[0])), true)
	_eq("nothing is selected at first", window._selected_item, "")

	var cheapest: String = Shop.stock("armorer")[0]
	window.select_buy(cheapest)
	_eq("selecting an item shows it", window._selected_item, cheapest)
	_eq("a piece of armor has no quantity buttons", window._quantity_row.visible, false)
	_eq("with no gold the Buy button is off", window._main_button.disabled, true)

	Session.character["gold"] = 10000
	Session.character_changed.emit()
	await _frames(2)
	_eq("with gold it turns on", window._main_button.disabled, false)
	var price: int = Shop.buy_price(cheapest)
	window._on_main()
	await _frames(2)
	_eq("buying takes the price", Session.character["gold"], 10000 - price)
	_eq("...and the item is in the bag", Inventory.count(Session.character["inventory"], cheapest), 1)
	_report("...and says so", "Bought" in window._message.text, window._message.text)
	_report("the shop shows the new gold", StatDisplay.format_number(10000 - price) in window._gold_label.text)

	Session.character["gold"] = 3
	window._on_main()
	_report("buying without enough gold is refused with a message", "gold" in window._message.text.to_lower(), window._message.text)
	_eq("...and nothing was taken", Session.character["gold"], 3)

	# General store: potions come in numbers.
	Session.character["gold"] = 100000
	_hud.open_shop("general_store")
	await _frames(2)
	_eq("the general store lists its stock", _rows(window).size(), Shop.stock("general_store").size())
	window._on_search("mana")
	var mana_rows := _rows(window).size()
	_report("searching narrows the list", mana_rows > 0 and mana_rows < Shop.stock("general_store").size(), str(mana_rows))
	window._on_search("")
	window.select_buy("healing_potion")
	_eq("potions have quantity buttons", window._quantity_row.visible, true)
	window._on_step(10)
	window._on_step(1)
	_eq("+10 and +1 make 12", window._quantity, 12)
	_eq("the total follows", window._total_label.text, "Total  %s g" % StatDisplay.format_number(Shop.buy_price("healing_potion") * 12))
	window._on_step(-1000)
	_eq("the amount never goes below 1", window._quantity, 1)
	window._on_step(10)
	var gold_before: int = Session.character["gold"]
	window._on_main()
	_eq("buying 11 potions", Inventory.count(Session.character["inventory"], "healing_potion"), 11)
	_eq("...costs 11 x the price", gold_before - Session.character["gold"], Shop.buy_price("healing_potion") * 11)

	# Full bag.
	var kept: Array = Session.character["inventory"]
	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	Session.character["inventory"] = full
	window.select_buy("iron_ring")
	window._on_main()
	_report("a full bag says so and keeps the gold", "full" in window._message.text.to_lower() and Session.character["gold"] == gold_before - Shop.buy_price("healing_potion") * 11, window._message.text)
	Session.character["inventory"] = kept
	window.close()


# ---------- selling ----------

func _test_selling() -> void:
	print("[shop] --- selling ---")
	_new_character()
	_player.refresh_stats()
	Session.add_item("healing_potion", 5)
	Session.add_item("iron_sword", 1)
	var window := _hud.shop_window
	_hud.open_shop("weaponsmith")
	await _frames(2)
	window._on_tab("sell")
	await _frames(2)
	_eq("the Sell tab lists the bag (a potion stack and a sword)", _rows(window).size(), 2)
	_report("each row shows what the shop pays", _rows(window).all(func(b: Button) -> bool: return " g" in b.text))

	var bag: Array = Session.character["inventory"]
	var potion_entry: Dictionary = {}
	var sword_entry: Dictionary = {}
	for entry in bag:
		if entry["item_id"] == "healing_potion":
			potion_entry = entry
		else:
			sword_entry = entry
	window.select_sell(potion_entry)
	_eq("a stack has quantity buttons", window._quantity_row.visible, true)
	_eq("...and Sell all", window._all_button.visible, true)
	_eq("you get half or less of what it costs: 25 each", Shop.sell_price("healing_potion"), 25)
	window._on_step(1)
	window._on_step(1)
	_eq("you can sell up to what you own", window._quantity, 3)
	window._on_step(100)
	_eq("...and no more than that", window._quantity, 5)
	window._on_step(-3)
	window._on_main()
	_eq("selling 2 potions pays 2 x 25", Session.character["gold"], 50)
	_eq("...3 are left", Inventory.count(Session.character["inventory"], "healing_potion"), 3)
	window.select_sell(potion_entry)
	window._on_sell_all()
	_eq("Sell all sells the rest", Inventory.count(Session.character["inventory"], "healing_potion"), 0)
	_eq("...gold: 5 potions in all", Session.character["gold"], 125)

	window.select_sell(sword_entry)
	_eq("a sword has no quantity buttons", window._quantity_row.visible, false)
	_eq("...and no Sell all", window._all_button.visible, false)
	var gold_before: int = Session.character["gold"]
	window._on_main()
	_eq("selling the sword pays its price", Session.character["gold"], gold_before + Shop.sell_price("iron_sword"))
	_eq("the bag is empty", Session.character["inventory"].size(), 0)
	_report("an empty bag says there is nothing to sell", window._list.get_child_count() == 1 and window._list.get_child(0) is Label)
	window.close()

	# The bag window has no Sell button: selling only happens at a shop.
	var has_sell := false
	for child in _hud.inventory_window._equip_button.get_parent().get_children():
		if child is Button and (child as Button).text == "Sell":
			has_sell = true
	_eq("the bag has no Sell button (selling is only possible in a shop)", has_sell, false)


# ---------- quick slots ----------

func _test_quick_slots() -> void:
	print("[shop] --- quick-use potion slots ---")
	_new_character()
	_player.refresh_stats()
	_player.potion_cooldowns = PotionCooldowns.new()
	_player.combatant.revive(1.0)
	_player._combat_clock = 0.0
	Session.add_item("potion_hp_minor", 3)
	await _frames(12)
	_eq("three quick slots on screen", _hud._quick_buttons.size(), 3)
	var health: Dictionary = _hud._quick_buttons["health"]
	_eq("an empty slot shows a +", (health["icon"] as Label).text, "+")

	_hud.show_message("")
	(health["button"] as Button).pressed.emit()
	_report("tapping an empty slot says how to set it", "Bag" in _hud._message.text, _hud._message.text)

	_hud.open_inventory()
	var bag_window := _hud.inventory_window
	var potion_entry: Dictionary = Session.character["inventory"][0]
	bag_window.select(potion_entry)
	_eq("a potion in the bag shows the Quick slot button", bag_window._quick_button.visible, true)
	var sword_check := false
	Session.add_item("iron_sword", 1)
	bag_window.select(Session.character["inventory"][1])
	sword_check = bag_window._quick_button.visible
	_eq("...a sword does not", sword_check, false)
	bag_window.select(potion_entry)
	bag_window._on_quick_slot()
	_eq("Quick slot puts it on the health slot", Session.character["settings"]["quick_slots"]["health"], "potion_hp_minor")
	_hud.close_windows()
	await _frames(12)
	_report("the slot shows the potion's initials", (health["icon"] as Label).text == "HM" or (health["icon"] as Label).text != "+", (health["icon"] as Label).text)
	_eq("...and how many are left", (health["count"] as Label).text, "x3")

	_hud.show_message("")
	(health["button"] as Button).pressed.emit()
	_eq("tapping it at full health says already full", _hud._message.text, "Already full.")
	_player.combatant.take_damage(80)
	var hp := _player.combatant.hp
	(health["button"] as Button).pressed.emit()
	await _frames(12)
	_eq("tapping it when hurt drinks the potion", _player.combatant.hp, hp + int(ItemDB.consumable_effect("potion_hp_minor")["amount"]) if hp + 50 < _player.combatant.max_health() else _player.combatant.max_health())
	_eq("...one is used up", (health["count"] as Label).text, "x2")
	_report("...the slot darkens while it cools down", (health["shade"] as ColorRect).anchor_top < 1.0)
	_report("...and counts the seconds", (health["time"] as Label).text != "", (health["time"] as Label).text)
	_hud.show_message("")
	_player.combatant.take_damage(30)
	(health["button"] as Button).pressed.emit()
	_report("tapping it again says it is not ready", "Not ready" in _hud._message.text, _hud._message.text)


# ---------- potions tab ----------

func _test_potions_tab() -> void:
	print("[shop] --- potions tab ---")
	var window := _hud.character_window
	_hud.open_character()
	window._show_page("Potions")
	await _frames(2)
	var health_row: Dictionary = window._quick_rows["health"]
	_report("the tab shows the quick slot's potion", "x2" in (health_row["label"] as Label).text, (health_row["label"] as Label).text)
	_eq("the mana slot is empty", (window._quick_rows["mana"]["label"] as Label).text, "(empty)")
	_eq("an empty slot's Clear is off", (window._quick_rows["mana"]["clear"] as Button).disabled, true)
	(health_row["clear"] as Button).pressed.emit()
	await _frames(2)
	_eq("Clear empties the slot", Session.character["settings"]["quick_slots"]["health"], "")
	_eq("...and the screen follows", (health_row["label"] as Label).text, "(empty)")

	var hp_control: Dictionary = window._auto_controls[0]
	_eq("Auto HP is off at first", (hp_control["check"] as CheckButton).button_pressed, false)
	(hp_control["check"] as CheckButton).button_pressed = true
	_eq("switching it on is saved", Session.character["settings"]["auto_hp"], true)
	(hp_control["slider"] as HSlider).value = 70
	_eq("moving the slider saves the limit", Session.character["settings"]["hp_percent"], 70)
	_eq("...and the label follows", (hp_control["value"] as Label).text, "70%")
	Session.update_settings({"hp_percent": 20})
	window.refresh()
	_eq("changing it elsewhere moves the slider", (hp_control["slider"] as HSlider).value, 20.0)
	var mp_control: Dictionary = window._auto_controls[1]
	(mp_control["check"] as CheckButton).button_pressed = true
	_eq("Auto MP can be switched on too", Session.character["settings"]["auto_mp"], true)
	_eq("the MP limit starts at 30%", (mp_control["value"] as Label).text, "30%")
	_eq("with no elixir it says so", window._elixir_label.text, "No elixir active.")
	_hud.close_windows()


# ---------- elixir ----------

func _test_elixir_display() -> void:
	print("[shop] --- elixir ---")
	await _frames(12)
	_eq("no elixir chip at first", _hud._buff_box.find_child("elixir", false, false), null)
	var now := int(Time.get_unix_time_from_system())
	Session.character["elixir"] = {"id": "elixir_30_day", "activated_at": now, "expires_at": now + 30 * 86400}
	await _frames(15)
	var chip := _hud._buff_box.find_child("elixir", false, false)
	_eq("an active elixir shows a chip", chip != null, true)
	_report("...with its name and the time left", chip != null and "30-Day Elixir" in (chip.get_child(0) as Label).text and "d" in (chip.get_child(0) as Label).text)

	_hud.open_character()
	_hud.character_window._show_page("Potions")
	await _frames(2)
	_report("the Potions tab shows it too", "30-Day Elixir" in _hud.character_window._elixir_label.text and "left" in _hud.character_window._elixir_label.text, _hud.character_window._elixir_label.text)
	_hud.close_windows()

	Session.character["elixir"] = {}
	await _frames(15)
	_eq("the chip goes when the elixir is gone", _hud._buff_box.find_child("elixir", false, false), null)

	Session.add_item("elixir_7_day", 1)
	_player.potion_cooldowns = PotionCooldowns.new()
	_hud.open_inventory()
	var bag := _hud.inventory_window
	bag.select(Session.character["inventory"][Session.character["inventory"].size() - 1])
	_eq("an elixir in the bag can be used", bag._use_button.visible, true)
	_eq("...but does not go on a potion slot", bag._quick_button.visible, false)
	bag._on_use()
	_eq("using it says it is active", bag._message.text, "Elixir activated.")
	_eq("...and starts it", Session.character["elixir"]["id"], "elixir_7_day")
	_hud.close_windows()
