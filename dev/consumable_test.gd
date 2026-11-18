extends Node
## DEV ONLY. Checks potion cooldowns, Auto Pots, elixirs, the shop, potion
## settings and saved health (M8). Needs no login and saves nothing. Run with F6.
## Your item sheet has no elixir items yet, so the test adds three pretend ones
## for the length of the test (see docs/elixir_items.csv for the real rows).

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character()
	_add_pretend_elixirs()

	_test_cooldowns()
	_test_auto_pot_logic()
	_test_elixir_rules()
	_test_shop_logic()
	_test_session_functions()
	await _build_arena()
	await _test_quick_slots_and_cooldowns()
	await _test_auto_pots_in_play()
	await _test_elixir_in_play()
	await _test_saved_vitals()

	Session.save_enabled = true
	Session.clear()
	print("[pots] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[pots] PASS  ", label)
	else:
		_failed += 1
		print("[pots] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_character() -> void:
	Session.character = {
		"name": "Fighter", "class_id": "warrior", "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
		"settings": AutoPot.default_settings(),
		"elixir": {}
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


func _bag(entries: Array) -> Array:
	var bag: Array = []
	for entry in entries:
		bag = Inventory.add(bag, entry[0], entry[1])["inventory"]
	return bag


func _amount(item_id: String) -> int:
	return int(ItemDB.consumable_effect(item_id)["amount"])


func _build_arena() -> void:
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	for camp in _world.camps:
		camp.queue_free()
	for node in get_tree().get_nodes_in_group("targetable"):
		node.queue_free()
	await _frames(3)


# ---------- cooldowns ----------

func _test_cooldowns() -> void:
	print("[pots] --- cooldowns ---")
	_near("a health potion cools down for 6 s", PotionCooldowns.duration_for("healing_potion"), 6.0)
	_near("a mana potion for 6 s", PotionCooldowns.duration_for("potion_mp_minor"), 6.0)
	_near("a stamina potion for 5 s", PotionCooldowns.duration_for("potion_sp_minor"), 5.0)
	_near("an unknown item gets the default 5 s", PotionCooldowns.duration_for("not_an_item"), 5.0)
	var rules: Dictionary = DataRegistry.get_config("consumable_rules")["cooldowns"]
	rules["overrides"]["healing_potion"] = 2.5
	_near("a hand-set override wins", PotionCooldowns.duration_for("healing_potion"), 2.5)
	rules["overrides"].erase("healing_potion")

	var cooldowns := PotionCooldowns.new()
	_eq("a potion starts ready", cooldowns.is_ready("healing_potion"), true)
	cooldowns.start("healing_potion", 2.0)
	_eq("after use it is not ready", cooldowns.is_ready("healing_potion"), false)
	_near("2 seconds left", cooldowns.remaining("healing_potion"), 2.0)
	_eq("another potion is not affected (individual cooldowns)", cooldowns.is_ready("potion_hp_minor"), true)
	cooldowns.update(1.0)
	_near("1 second left", cooldowns.remaining("healing_potion"), 1.0)
	_near("half of the cooldown is left", cooldowns.fraction("healing_potion"), 0.5)
	cooldowns.update(1.5)
	_eq("ready again", cooldowns.is_ready("healing_potion"), true)
	_near("nothing left", cooldowns.remaining("healing_potion"), 0.0)


# ---------- Auto Pot decisions ----------

func _state(hp: int, mp: int, bag: Array, settings: Dictionary, cooldowns: PotionCooldowns = null) -> Dictionary:
	return {"hp": hp, "max_hp": 100, "mp": mp, "max_mp": 100, "settings": settings, "inventory": bag,
			"cooldowns": cooldowns if cooldowns != null else PotionCooldowns.new()}


func _test_auto_pot_logic() -> void:
	print("[pots] --- auto pots ---")
	var defaults := AutoPot.default_settings()
	_eq("Auto Pots start off", [defaults["auto_hp"], defaults["auto_mp"]], [false, false])
	_eq("default limits are 50% and 30%", [defaults["hp_percent"], defaults["mp_percent"]], [50, 30])
	_eq("three quick slots", defaults["quick_slots"].keys(), ["health", "mana", "stamina"])

	var on := defaults.duplicate(true)
	on["auto_hp"] = true
	on["auto_mp"] = true
	var bag := _bag([["potion_hp_minor", 3], ["potion_mp_minor", 2]])

	_eq("health at 40% is under the 50% limit: a health potion is chosen",
			AutoPot.choose(_state(40, 100, bag, on)).filter(func(p: Dictionary) -> bool: return p["resource"] == "health").size(), 1)
	_eq("health at 50% counts (the limit is inclusive)",
			AutoPot.choose(_state(50, 100, bag, on)).filter(func(p: Dictionary) -> bool: return p["resource"] == "health").size(), 1)
	_eq("health at 60% does nothing", AutoPot.choose(_state(60, 100, bag, on)).filter(func(p: Dictionary) -> bool: return p["resource"] == "health"), [])
	_eq("full health does nothing", AutoPot.choose(_state(100, 100, bag, on)).filter(func(p: Dictionary) -> bool: return p["resource"] == "health"), [])
	_eq("mana at 20% is under the 30% limit: a mana potion is chosen",
			AutoPot.choose(_state(100, 20, bag, on))[0]["resource"], "mana")
	_eq("mana at 40% does nothing", AutoPot.choose(_state(100, 40, bag, on)), [])
	_eq("both low: one of each", AutoPot.choose(_state(10, 10, bag, on)).size(), 2)
	_eq("a dead player drinks nothing", AutoPot.choose(_state(0, 10, bag, on)).filter(func(p: Dictionary) -> bool: return p["resource"] == "health"), [])

	var off := defaults.duplicate(true)
	_eq("with Auto Pots off nothing is chosen", AutoPot.choose(_state(5, 5, bag, off)), [])
	var only_hp := off.duplicate(true)
	only_hp["auto_hp"] = true
	_eq("only the enabled one is used", AutoPot.choose(_state(5, 5, bag, only_hp)).size(), 1)
	_eq("no potions in the bag: nothing to drink", AutoPot.choose(_state(5, 5, [], on)), [])
	_eq("a mana potion is not used for health", AutoPot.choose(_state(5, 100, _bag([["potion_mp_minor", 2]]), on)), [])

	var assigned := on.duplicate(true)
	assigned["quick_slots"]["health"] = "potion_hp_standard"
	var mixed := _bag([["potion_hp_minor", 2], ["potion_hp_standard", 1]])
	_eq("the potion on the quick slot is preferred", AutoPot.choose(_state(10, 100, mixed, assigned))[0]["item_id"], "potion_hp_standard")
	var cooling := PotionCooldowns.new()
	cooling.start("potion_hp_standard", 5.0)
	_eq("if it is cooling down, another potion is used instead", AutoPot.choose(_state(10, 100, mixed, assigned, cooling))[0]["item_id"], "potion_hp_minor")
	cooling.start("potion_hp_minor", 5.0)
	_eq("if all of them are cooling down, nothing is used", AutoPot.choose(_state(10, 100, mixed, assigned, cooling)), [])

	# Picking the right size.
	var sizes := _bag([["potion_hp_minor", 1], ["potion_hp_small", 1], ["potion_hp_lesser", 1]])
	var small_amount := _amount("potion_hp_small")
	_eq("the smallest potion that fills the gap is picked", AutoPot.pick_potion("health", small_amount - 10, sizes, PotionCooldowns.new()), "potion_hp_small")
	_eq("a tiny gap gets the smallest potion", AutoPot.pick_potion("health", 5, sizes, PotionCooldowns.new()), "potion_hp_minor")
	_eq("a huge gap gets the biggest available", AutoPot.pick_potion("health", 100000, sizes, PotionCooldowns.new()), "potion_hp_lesser")
	var small_cooling := PotionCooldowns.new()
	small_cooling.start("potion_hp_small", 5.0)
	_eq("a potion on cooldown is skipped", AutoPot.pick_potion("health", small_amount - 10, sizes, small_cooling), "potion_hp_lesser")
	_eq("nothing fits an empty bag", AutoPot.pick_potion("health", 10, [], PotionCooldowns.new()), "")


# ---------- elixirs ----------

func _test_elixir_rules() -> void:
	print("[pots] --- elixirs ---")
	_eq("three elixir types", ElixirRules.types().keys().size(), 3)
	_eq("an elixir is recognised", ElixirRules.is_elixir("elixir_7_day"), true)
	_eq("a potion is not an elixir", ElixirRules.is_elixir("healing_potion"), false)
	_eq("time text: days", ElixirRules.time_text(6 * 86400 + 4 * 3600), "6d 4h")
	_eq("time text: hours", ElixirRules.time_text(5 * 3600 + 12 * 60), "5h 12m")
	_eq("time text: minutes", ElixirRules.time_text(180), "3m")
	_eq("time text: under a minute", ElixirRules.time_text(20), "1m")

	var now := 1000000
	var seven := ElixirRules.activate({}, "elixir_7_day", now)
	_eq("a new elixir can be activated", seven["ok"], true)
	_eq("...it lasts 7 days", seven["elixir"]["expires_at"] - seven["elixir"]["activated_at"], 7 * 86400)
	_eq("...nothing was replaced", seven["replaced"], false)
	_eq("it is active", ElixirRules.is_active(seven["elixir"], now + 100), true)
	_eq("...until it runs out", ElixirRules.is_active(seven["elixir"], now + 7 * 86400), false)
	_eq("seconds left", ElixirRules.seconds_left(seven["elixir"], now + 86400), 6 * 86400)
	_eq("nothing active means no time left", ElixirRules.seconds_left({}, now), 0)

	var thirty := ElixirRules.activate(seven["elixir"], "elixir_30_day", now + 10)
	_eq("a stronger elixir replaces a weaker one", [thirty["ok"], thirty["replaced"]], [true, true])
	var weaker := ElixirRules.activate(thirty["elixir"], "elixir_7_day", now + 20)
	_eq("a weaker elixir can not replace a stronger active one", weaker["error"], "WEAKER_ELIXIR")
	var same := ElixirRules.activate(seven["elixir"], "elixir_7_day", now + 5)
	_eq("the same elixir renews itself", [same["ok"], same["replaced"]], [true, true])
	var after_expiry := ElixirRules.activate(seven["elixir"], "elixir_7_day", now + 8 * 86400)
	_eq("an expired elixir does not block a new one", [after_expiry["ok"], after_expiry["replaced"]], [true, false])
	_eq("an unknown item is refused", ElixirRules.activate({}, "healing_potion", now)["error"], "NOT_AN_ELIXIR")

	var rules: Dictionary = DataRegistry.get_config("consumable_rules")["elixirs"]
	rules["replace_rule"] = "always"
	_eq("with the 'always' rule a weaker elixir replaces too", ElixirRules.activate(thirty["elixir"], "elixir_7_day", now + 20)["ok"], true)
	rules["replace_rule"] = "higher_or_equal"

	_eq("30-day elixir: 1% of 1000", ElixirRules.tick_amounts(thirty["elixir"], 1000, 1000, 1000)["hp"], 10)
	_eq("7-day elixir: 0.5% of 1000", ElixirRules.tick_amounts(seven["elixir"], 1000, 1000, 1000)["hp"], 5)
	_eq("a tiny bar still gets 1", ElixirRules.tick_amounts(seven["elixir"], 50, 50, 50)["hp"], 1)
	_eq("a bar that does not exist gets 0", ElixirRules.tick_amounts(seven["elixir"], 100, 0, 100)["mp"], 0)

	var record := {"id": "elixir_7_day", "activated_at": 1000, "expires_at": 1000 + 86400}
	_eq("100 seconds is 10 ticks", ElixirRules.ticks_between(record, 1000, 1100), 10)
	_eq("time before it was activated does not count", ElixirRules.ticks_between(record, 0, 1100), 10)
	_eq("time after it ran out does not count", ElixirRules.ticks_between(record, 1000, 1000 + 86400 + 5000), 8640)
	_eq("no time, no ticks", ElixirRules.ticks_between(record, 2000, 2000), 0)
	_eq("no elixir, no ticks", ElixirRules.ticks_between({}, 0, 100000), 0)
	var week := {"id": "elixir_7_day", "activated_at": 0, "expires_at": 7 * 86400}
	_eq("being away for 3 days counts only 24 hours of it", ElixirRules.ticks_between(week, 0, 3 * 86400, true), 8640)
	_eq("...but without the offline limit it counts all 3 days", ElixirRules.ticks_between(week, 0, 3 * 86400, false), 25920)


# ---------- shop ----------

func _test_shop_logic() -> void:
	print("[pots] --- shop ---")
	_eq("five shops", Shop.shop_ids().size(), 5)
	var weapons := Shop.stock("weaponsmith")
	_eq("the weaponsmith sells the 7 weapons", weapons.size(), 7)
	var all_weapons := true
	for item_id in weapons:
		if ItemDB.category(item_id) != "weapon":
			all_weapons = false
	_eq("...only weapons", all_weapons, true)
	var cheapest_first := true
	for i in range(1, weapons.size()):
		if Shop.buy_price(weapons[i]) < Shop.buy_price(weapons[i - 1]):
			cheapest_first = false
	_eq("...cheapest first", cheapest_first, true)
	_eq("the armorer sells the 6 armor pieces", Shop.stock("armorer").size(), 6)
	_eq("the jeweler sells the 4 accessories", Shop.stock("jeweler").size(), 4)
	_eq("the mount vendor sells the 3 mounts", Shop.stock("mount_vendor").size(), 3)
	var consumables := 0
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.category(item_id) == "consumable" and Shop.buy_price(item_id) > 0 and not ElixirRules.is_elixir(item_id):
			consumables += 1
	var general := 0
	for item_id in Shop.stock("general_store"):
		if not ElixirRules.is_elixir(item_id):
			general += 1
	_eq("the general store sells every potion and food that has a price", general, consumables)
	_eq("an unknown shop sells nothing", Shop.stock("nowhere"), [])

	var bad := 0
	var overpriced: Array = []
	for item_id in DataRegistry.get_ids("items"):
		if Shop.buy_price(item_id) > 0 and Shop.sell_price(item_id) > Shop.buy_price(item_id) / 2:
			bad += 1
			overpriced.append(item_id)
	_eq("no item sells for more than half of its price", bad, 0)
	_eq("a potion the sheet sells for 75 sells for 25 (half of 50)", Shop.sell_price("healing_potion"), 25)
	_eq("iron armor: the sheet says 250, the shop pays half of 150", Shop.sell_price("iron_armor"), 75)

	var bag := _bag([["iron_sword", 1]])
	var bought := Shop.buy(1000, bag, "healing_potion", 3)
	_eq("buying works", bought["ok"], true)
	_eq("...3 potions cost 150", [bought["cost"], bought["gold"]], [150, 850])
	_eq("...they are in the bag", Inventory.count(bought["inventory"], "healing_potion"), 3)
	_eq("...the original bag is unchanged", Inventory.count(bag, "healing_potion"), 0)
	_eq("not enough gold", Shop.buy(10, bag, "healing_potion", 1)["error"], "NOT_ENOUGH_GOLD")
	_eq("an unknown item", Shop.buy(1000, bag, "not_an_item", 1)["error"], "UNKNOWN_ITEM")
	_eq("amount 0", Shop.buy(1000, bag, "healing_potion", 0)["error"], "INVALID_AMOUNT")
	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	_eq("a full bag stops buying (and keeps the gold)", Shop.buy(1000, full, "iron_ring", 1)["error"], "INVENTORY_FULL")

	var sold := Shop.sell(0, bought["inventory"], "healing_potion", 2)
	_eq("selling 2 potions pays 2 x 25", [sold["ok"], sold["earned"], sold["gold"]], [true, 50, 50])
	_eq("...they left the bag", Inventory.count(sold["inventory"], "healing_potion"), 1)
	var sword_uid: String = bag[0]["uid"]
	var sold_sword := Shop.sell(0, bag, "iron_sword", 1, sword_uid)
	_eq("selling a piece of gear by its id", [sold_sword["ok"], sold_sword["earned"]], [true, Shop.sell_price("iron_sword")])
	_eq("...it left the bag", sold_sword["inventory"].size(), 0)
	_eq("selling what you do not have", Shop.sell(0, bag, "healing_potion", 1)["error"], "NOT_ENOUGH_ITEMS")
	_eq("selling more than you have", Shop.sell(0, bought["inventory"], "healing_potion", 9)["error"], "NOT_ENOUGH_ITEMS")


# ---------- Session: settings, shop, elixir ----------

func _test_session_functions() -> void:
	print("[pots] --- saved settings and shop in the Session ---")
	_new_character()
	_eq("a new character has the default settings", Session.character["settings"]["hp_percent"], 50)
	_eq("...and no elixir", Session.character["elixir"], {})

	_eq("turn on Auto HP", Session.update_settings({"auto_hp": true})["ok"], true)
	_eq("...it is saved on the character", Session.character["settings"]["auto_hp"], true)
	Session.update_settings({"hp_percent": 99})
	_eq("a limit above the maximum is kept at 95", Session.character["settings"]["hp_percent"], 95)
	Session.update_settings({"hp_percent": 1})
	_eq("a limit below the minimum is kept at 5", Session.character["settings"]["hp_percent"], 5)
	_eq("an unknown setting is refused", Session.update_settings({"cheat": true})["error"], "UNKNOWN_SETTING")

	_eq("a health potion goes on the health slot", Session.set_quick_slot("health", "potion_hp_minor")["ok"], true)
	_eq("...it is remembered", Session.character["settings"]["quick_slots"]["health"], "potion_hp_minor")
	_eq("a mana potion does not fit the health slot", Session.set_quick_slot("health", "potion_mp_minor")["error"], "WRONG_SLOT")
	_eq("an unknown slot", Session.set_quick_slot("luck", "potion_hp_minor")["error"], "UNKNOWN_SLOT")
	_eq("an empty name clears a slot", Session.set_quick_slot("health", "")["ok"], true)
	_eq("...cleared", Session.character["settings"]["quick_slots"]["health"], "")

	Session.character["gold"] = 1000
	var bought := Session.buy_item("healing_potion", 4)
	_eq("buying in the Session works", bought["ok"], true)
	_eq("...gold and bag changed together", [Session.character["gold"], Inventory.count(Session.character["inventory"], "healing_potion")], [800, 4])
	var poor := Session.buy_item("iron_armor", 100)
	_eq("buying too much fails", poor["error"], "NOT_ENOUGH_GOLD")
	_eq("...and changes neither gold nor bag", [Session.character["gold"], Inventory.count(Session.character["inventory"], "healing_potion")], [800, 4])
	var sold := Session.sell_item("healing_potion", 4)
	_eq("selling in the Session works", [sold["ok"], sold["earned"]], [true, 100])
	_eq("...gold went up", Session.character["gold"], 900)

	Session.character["inventory"].append({"item_id": "elixir_7_day", "qty": 2})
	var drunk := Session.activate_elixir("elixir_7_day", 1000000)
	_eq("drinking an elixir works", drunk["ok"], true)
	_eq("...it is recorded with its end time", Session.character["elixir"]["expires_at"], 1000000 + 7 * 86400)
	_eq("...one elixir is used up", Inventory.count(Session.character["inventory"], "elixir_7_day"), 1)
	_eq("a weaker elixir while a stronger one is active is refused",
			Session.activate_elixir("elixir_7_day", 1000100)["ok"], true)    # same rank renews
	Session.character["inventory"].append({"item_id": "elixir_30_day", "qty": 1})
	Session.activate_elixir("elixir_30_day", 1000200)
	Session.character["inventory"].append({"item_id": "elixir_7_day", "qty": 1})
	var refused := Session.activate_elixir("elixir_7_day", 1000300)
	_eq("a weaker one can not replace the 30-day elixir", refused["error"], "WEAKER_ELIXIR")
	_eq("...and is not used up", Inventory.count(Session.character["inventory"], "elixir_7_day"), 1)
	Session.clear_elixir()
	_eq("an elixir can be cleared", Session.character["elixir"], {})

	var changes := 0
	var listener := func() -> void: changes += 1
	Session.character_changed.connect(listener)
	Session.record_vitals(50, 20, 10)
	_eq("health is remembered", Session.character["vitals"], {"hp": 50, "mp": 20, "sp": 10})
	_eq("...without bothering the screens", changes, 0)
	Session._dirty.clear()
	Session.record_vitals(50, 20, 10)
	_eq("the same values are not saved again", Session.has_unsaved_changes(), false)
	Session.character_changed.disconnect(listener)


# ---------- using things in play ----------

func _test_quick_slots_and_cooldowns() -> void:
	print("[pots] --- quick slots in play ---")
	_new_character()
	Session.record_vitals(0, 0, 0)
	Session.character.erase("vitals")
	_player.refresh_stats()
	_player.potion_cooldowns = PotionCooldowns.new()
	_player.combatant.revive(1.0)
	_eq("an empty slot says to set a potion", _player.use_quick_slot("health")["error"], "NO_SLOT")
	Session.set_quick_slot("health", "potion_hp_minor")
	_eq("a slot with no potions left says so", _player.use_quick_slot("health")["error"], "NO_POTION")

	Session.add_item("potion_hp_minor", 3)
	_player.combatant.take_damage(80)
	var hp := _player.combatant.hp
	var used := _player.use_quick_slot("health")
	_eq("the quick slot drinks its potion", used["ok"], true)
	_eq("...health went up", _player.combatant.hp, hp + _amount("potion_hp_minor"))
	_eq("...one potion was used up", Inventory.count(Session.character["inventory"], "potion_hp_minor"), 2)
	var again := _player.use_quick_slot("health")
	_eq("the same potion is on cooldown", again["error"], "COOLDOWN")
	_report("...the message says how long", "(" in again["message"], again["message"])
	_near("...for about 6 seconds", _player.potion_cooldowns.remaining("potion_hp_minor"), 6.0, 0.2)

	Session.add_item("potion_hp_small", 1)
	_eq("a different potion is not blocked (individual cooldowns)", _player.use_consumable("potion_hp_small")["ok"], true)
	await _frames(400)
	_eq("after 6+ seconds the first potion is ready again", _player.potion_cooldowns.is_ready("potion_hp_minor"), true)


func _test_auto_pots_in_play() -> void:
	print("[pots] --- auto pots in play ---")
	_new_character()
	_player.refresh_stats()
	_player.potion_cooldowns = PotionCooldowns.new()
	_player.combatant.revive(1.0)
	_player._combat_clock = 0.0       # no natural regeneration during this test
	Session.add_item("potion_hp_minor", 3)
	var maximum := _player.combatant.max_health()

	_player.combatant.take_damage(maximum - 40)          # 40 left of 134 = about 30%
	await _frames(40)
	_eq("with Auto Pots off nothing is drunk", Inventory.count(Session.character["inventory"], "potion_hp_minor"), 3)

	Session.update_settings({"auto_hp": true, "hp_percent": 50})
	await _frames(40)
	_eq("with Auto HP on and health under the limit, a potion is drunk", Inventory.count(Session.character["inventory"], "potion_hp_minor"), 2)
	_report("...and health went up", _player.combatant.hp > 40)
	_eq("...that potion is now cooling down", _player.potion_cooldowns.is_ready("potion_hp_minor"), false)

	_player.combatant.take_damage(_player.combatant.hp - 5)
	await _frames(60)
	_eq("while it cools down, no second one of the same potion is drunk", Inventory.count(Session.character["inventory"], "potion_hp_minor"), 2)
	Session.add_item("potion_hp_small", 1)
	await _frames(40)
	_eq("a different potion is drunk right away", Inventory.count(Session.character["inventory"], "potion_hp_small"), 0)

	# Healthy: nothing happens.
	_player.combatant.heal(100000)
	_player.potion_cooldowns = PotionCooldowns.new()
	var before: int = Inventory.count(Session.character["inventory"], "potion_hp_minor")
	await _frames(40)
	_eq("with full health nothing is drunk", Inventory.count(Session.character["inventory"], "potion_hp_minor"), before)

	# Mana.
	Session.update_settings({"auto_mp": true, "mp_percent": 30})
	Session.add_item("potion_mp_minor", 2)
	_player.combatant.mp = 1
	await _frames(40)
	_eq("a mana potion is drunk when mana is low", Inventory.count(Session.character["inventory"], "potion_mp_minor"), 1)
	_report("...and mana went up", _player.combatant.mp > 1)

	# The dead drink nothing.
	Session.update_settings({"auto_mp": false})
	_player.combatant.take_damage(_player.combatant.hp)
	var count_before: int = Inventory.count(Session.character["inventory"], "potion_hp_minor")
	_player.potion_cooldowns = PotionCooldowns.new()
	await _frames(40)
	_eq("a dead player drinks nothing", Inventory.count(Session.character["inventory"], "potion_hp_minor"), count_before)
	_player.revive()
	await _frames(3)


func _test_elixir_in_play() -> void:
	print("[pots] --- elixir in play ---")
	_new_character()
	_player.refresh_stats()
	_player.potion_cooldowns = PotionCooldowns.new()
	_player.combatant.revive(1.0)
	_player._combat_clock = 0.0
	var now := 5000000
	_player.clock_override = now
	var rules: Dictionary = DataRegistry.get_config("consumable_rules")["elixirs"]
	rules["tick_seconds"] = 1.0                       # fast ticks for the test

	Session.character["inventory"].append({"item_id": "elixir_30_day", "qty": 1})
	var drunk := _player.use_consumable("elixir_30_day")
	_eq("drinking an elixir from the bag works", drunk["ok"], true)
	_eq("...it is active", ElixirRules.is_active(Session.character["elixir"], now), true)
	_eq("...and the elixir is used up", Inventory.count(Session.character["inventory"], "elixir_30_day"), 0)

	_player.combatant.take_damage(100)
	var hp := _player.combatant.hp
	await _frames(130)         # a little over 2 seconds
	var gained := _player.combatant.hp - hp
	_eq("the elixir heals 1% of max health each tick (1 of 134), twice in 2+ seconds", gained, 2)
	_player.combatant.mp = 1
	await _frames(70)
	_report("...and gives mana too", _player.combatant.mp > 1)

	_player.clock_override = now + 31 * 86400
	await _frames(5)
	_eq("when it runs out, it is cleared", Session.character["elixir"], {})
	_player._combat_clock = 0.0          # keep the natural slow recovery out of this measurement
	var hp_after := _player.combatant.hp
	await _frames(130)
	_eq("...and heals no more", _player.combatant.hp, hp_after)
	rules["tick_seconds"] = 10.0
	_player.clock_override = -1


func _test_saved_vitals() -> void:
	print("[pots] --- saved health and offline healing ---")
	var now := int(Time.get_unix_time_from_system())
	var iso := Time.get_datetime_string_from_unix_time(now - 100)

	# A saved character with a 30-day elixir active, away for 100 seconds.
	_new_character()
	Session.character["vitals"] = {"hp": 10, "mp": 5, "sp": 5}
	Session.character["elixir"] = {"id": "elixir_30_day", "activated_at": now - 5000, "expires_at": now + 86400}
	Session.character["updated_at"] = iso
	var world: Node3D = load("res://maps/world_test.tscn").instantiate()
	add_child(world)
	await _frames(3)
	var player: PlayerController = world.player
	_eq("away 100 s with a 30-day elixir: 10 ticks of 1% = +10 health", player.combatant.hp, 20)
	_eq("...the elixir is still active", Session.character["elixir"].is_empty(), false)
	world.queue_free()
	await _frames(3)

	# Without an elixir you come back with what you left with.
	_new_character()
	Session.character["vitals"] = {"hp": 30, "mp": 7, "sp": 9}
	world = load("res://maps/world_test.tscn").instantiate()
	add_child(world)
	await _frames(3)
	player = world.player
	_eq("without an elixir you keep your saved health", player.combatant.hp, 30)
	_eq("...mana", player.combatant.mp, 7)
	world.queue_free()
	await _frames(3)

	# A character saved dead does not come back dead.
	_new_character()
	Session.character["vitals"] = {"hp": 0, "mp": 0, "sp": 0}
	world = load("res://maps/world_test.tscn").instantiate()
	add_child(world)
	await _frames(3)
	player = world.player
	_eq("saved at 0 health: you come back with full health", player.combatant.hp, player.combatant.max_health())
	world.queue_free()
	await _frames(3)

	# Health is remembered while playing.
	_new_character()
	world = load("res://maps/world_test.tscn").instantiate()
	add_child(world)
	await _frames(3)
	player = world.player
	for camp in world.camps:
		camp.queue_free()
	player.combatant.take_damage(33)
	await _frames(200)
	_eq("health is remembered a few seconds after it changes", Session.character.get("vitals", {}).get("hp", -1), player.combatant.hp)
	world.queue_free()
