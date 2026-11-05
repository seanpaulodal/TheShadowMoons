extends Node
## DEV ONLY. Checks ItemDB, Inventory and Equipment against your real item data
## (M3.1 / M3.4 / M3.5). Run with F6 and read the Output panel.
## Lines that start with "[items] PASS" / "FAIL" are the checks. Lines that start
## with "[items] note" are things in the data worth knowing about (not failures).
## The expected numbers use the placeholder class data (warrior at level 1).

var _passed: int = 0
var _failed: int = 0
var _warrior := {"level": 1, "class_id": "warrior"}


func _ready() -> void:
	await get_tree().process_frame
	_test_item_db()
	_test_data_health()
	_test_inventory()
	_test_equipment()
	print("[items] RESULT: %d passed, %d failed" % [_passed, _failed])


func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float) -> void:
	_report(label, absf(got - expected) < 0.011, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String) -> void:
	if passed:
		_passed += 1
		print("[items] PASS  ", label)
	else:
		_failed += 1
		print("[items] FAIL  %s  (%s)" % [label, detail])


func _warrior_stats(equipped: Dictionary, mounted: bool = false) -> Dictionary:
	return StatCalculator.calculate("warrior", 1, {}, Equipment.modifiers(equipped, mounted))["stats"]


# Puts a piece of gear into a fresh bag and returns {"inventory", "uid"}.
func _bag_with(items: Array) -> Dictionary:
	var bag: Array = []
	var uids := {}
	for item_id in items:
		var added := Inventory.add(bag, item_id, 1)
		bag = added["inventory"]
		uids[item_id] = str(bag[bag.size() - 1].get("uid", ""))    # stackable items have no uid
	return {"inventory": bag, "uids": uids}


# ---------- ItemDB ----------

func _test_item_db() -> void:
	print("[items] --- ItemDB ---")
	_eq("72 items loaded", DataRegistry.get_ids("items").size(), 72)
	_eq("item_rules loaded", DataRegistry.get_config("item_rules").is_empty(), false)
	_eq("name", ItemDB.display_name("flame_blade"), "Flame Blade")
	_eq("category is lower case", ItemDB.category("flame_blade"), "weapon")
	_eq("potions stack", ItemDB.is_stackable("healing_potion"), true)
	_eq("swords do not stack", ItemDB.is_stackable("iron_sword"), false)
	_eq("equip slot of a helmet", ItemDB.equip_slot("iron_helm"), "helmet")
	_eq("equip slot of boots", ItemDB.equip_slot("leather_boots"), "boots")
	_eq("potions have no equip slot", ItemDB.equip_slot("healing_potion"), "")
	_eq("scrolls have no equip slot", ItemDB.equip_slot("fireball_spell"), "")
	_eq("default level requirement", ItemDB.level_req("iron_sword"), 1)
	_eq("default class requirement (all classes)", ItemDB.class_req("iron_sword"), [])
	_eq("unknown item is not found", ItemDB.exists("not_an_item"), false)

	_eq("flame_blade damage range", ItemDB.weapon_damage("flame_blade"), {"min": 45, "max": 70})
	_eq("armor has no damage range", ItemDB.weapon_damage("iron_armor"), {})
	_eq("flame_blade element", ItemDB.element_damage("flame_blade"), {"element": "Fire", "amount": 25.0})
	_eq("wooden_sword has no element (0)", ItemDB.element_damage("wooden_sword"), {})
	_eq("armor has no element (N/A)", ItemDB.element_damage("iron_armor"), {})
	var burn := ItemDB.on_hit_status("flame_blade")
	_eq("flame_blade on-hit effect", burn["effect"], "Burn")
	_near("flame_blade on-hit chance", burn["chance"], 0.25)
	_eq("'NaN' status text means no status", ItemDB.on_hit_status("wooden_sword"), {})
	_eq("potion effect", ItemDB.consumable_effect("healing_potion"), {"resource": "health", "amount": 25})
	_eq("SP potion restores stamina", ItemDB.consumable_effect("potion_sp_minor")["resource"], "stamina")
	_eq("sword gives no consumable effect", ItemDB.consumable_effect("iron_sword"), {})
	_eq("vendors read from the status column", ItemDB.vendors("leather_boots"), ["GeneralStore", "ArmorSmith"])
	_eq("weapons list no vendors", ItemDB.vendors("iron_sword"), [])
	_eq("drop sources", ItemDB.drop_sources("iron_helm"), ["skeleton_lord"])
	_eq("no drop sources for mounts", ItemDB.drop_sources("shadow_steed_mount"), [])

	var sword_mods := ItemDB.stat_modifiers("wooden_sword")
	var by_stat := {}
	for modifier in sword_mods:
		by_stat[modifier["stat"]] = modifier["flat"]
	_near("wooden_sword atk_power bonus", by_stat["atk_power"], 15.0)
	_near("wooden_sword crit_chance bonus (0.05 -> 5 points)", by_stat["crit_chance"], 5.0)
	_near("wooden_sword crit_damage bonus (1.25 -> +25 points)", by_stat["crit_damage"], 25.0)
	_eq("potions give no stat bonuses", ItemDB.stat_modifiers("healing_potion"), [])


func _test_data_health() -> void:
	print("[items] --- data health ---")
	var report := ItemDB.validate()
	_eq("no item data errors", report["errors"], [])
	for message in report["errors"]:
		print("[items] ERROR ", message)
	var icon_warnings := 0
	for message in report["warnings"]:
		if "icon not found" in message:
			icon_warnings += 1
		else:
			print("[items] note  ", message)
	print("[items] note  %d item icons were not found on disk (normal if the icon files are not in this project)" % icon_warnings)


# ---------- Inventory ----------

func _test_inventory() -> void:
	print("[items] --- Inventory ---")
	var empty: Array = []
	var first := Inventory.add(empty, "healing_potion", 5)
	_eq("add 5 potions: ok", first["ok"], true)
	_eq("...one stack", first["inventory"].size(), 1)
	_eq("...count", Inventory.count(first["inventory"], "healing_potion"), 5)
	_eq("original bag untouched", empty.size(), 0)

	var big := Inventory.add(first["inventory"], "healing_potion", 1000)
	_eq("add 1000 more: 1005 total", Inventory.count(big["inventory"], "healing_potion"), 1005)
	_eq("...split into 2 stacks (max 999)", big["inventory"].size(), 2)
	_eq("...first stack is full", big["inventory"][0]["qty"], 999)

	var removed := Inventory.remove(big["inventory"], "healing_potion", 10)
	_eq("remove 10: 995 left", Inventory.count(removed["inventory"], "healing_potion"), 995)
	var too_many := Inventory.remove(big["inventory"], "healing_potion", 5000)
	_eq("removing more than you have fails", too_many["error"], "NOT_ENOUGH_ITEMS")
	var all_gone := Inventory.remove(first["inventory"], "healing_potion", 5)
	_eq("removing everything empties the stack", all_gone["inventory"].size(), 0)

	var swords := Inventory.add(empty, "iron_sword", 3)
	_eq("3 swords use 3 slots", swords["inventory"].size(), 3)
	var uids := {}
	for entry in swords["inventory"]:
		uids[entry["uid"]] = true
	_eq("every sword has its own unique id", uids.size(), 3)

	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	_eq("bag fills to its limit", full.size(), Inventory.max_slots())
	var overflow := Inventory.add(full, "iron_sword", 1)
	_eq("adding to a full bag fails", overflow["error"], "INVENTORY_FULL")
	_eq("...and changes nothing", full.size(), Inventory.max_slots())
	_eq("a full bag still tops up an existing stack",
			Inventory.add(first["inventory"], "healing_potion", 1)["ok"], true)
	_eq("unknown item is refused", Inventory.add(empty, "not_an_item", 1)["error"], "UNKNOWN_ITEM")
	_eq("amount 0 is refused", Inventory.add(empty, "healing_potion", 0)["error"], "INVALID_AMOUNT")


# ---------- Equipment ----------

func _test_equipment() -> void:
	print("[items] --- Equipment ---")
	var base := _warrior_stats({})
	_eq("warrior base atk_power", base["atk_power"], 21)

	var bag := _bag_with(["wooden_sword", "iron_armor", "iron_helm", "iron_gloves", "iron_boots",
			"iron_ring", "ring_of_vigor", "iron_necklace", "shadow_steed_mount", "healing_potion"])
	var inventory: Array = bag["inventory"]
	var uids: Dictionary = bag["uids"]
	var equipped := {}

	var step := Equipment.equip(inventory, equipped, uids["wooden_sword"], _warrior)
	_eq("equip weapon: ok", step["ok"], true)
	inventory = step["inventory"]
	equipped = step["equipped"]
	_eq("...it left the bag", Inventory.find_uid(inventory, uids["wooden_sword"]), -1)
	_eq("...it is in the weapon slot", equipped["weapon"]["item_id"], "wooden_sword")
	var stats := _warrior_stats(equipped)
	_eq("...atk_power 21 + 15", stats["atk_power"], 36)
	_near("...crit_chance 5.8 + 5", stats["crit_chance"], 10.8)
	_near("...crit_damage 151 + 25", stats["crit_damage"], 176.0)

	for item_id in ["iron_armor", "iron_helm", "iron_gloves", "iron_boots"]:
		step = Equipment.equip(inventory, equipped, uids[item_id], _warrior)
		inventory = step["inventory"]
		equipped = step["equipped"]
	_eq("armor pieces go to their own slots",
			[equipped["armor"]["item_id"], equipped["helmet"]["item_id"], equipped["gloves"]["item_id"], equipped["boots"]["item_id"]],
			["iron_armor", "iron_helm", "iron_gloves", "iron_boots"])
	_eq("defense 12 + 25 + 12 + 25 + 25", _warrior_stats(equipped)["def_power"], 99)

	step = Equipment.equip(inventory, equipped, uids["iron_ring"], _warrior)
	inventory = step["inventory"]
	equipped = step["equipped"]
	step = Equipment.equip(inventory, equipped, uids["ring_of_vigor"], _warrior)
	inventory = step["inventory"]
	equipped = step["equipped"]
	_eq("first ring takes ring_1", equipped["ring_1"]["item_id"], "iron_ring")
	_eq("second ring takes ring_2", equipped["ring_2"]["item_id"], "ring_of_vigor")
	_eq("both ring bonuses count: max_health 134 + 50", _warrior_stats(equipped)["max_health"], 184)
	_eq("both ring bonuses count: defense 99 + 25", _warrior_stats(equipped)["def_power"], 124)

	step = Equipment.equip(inventory, equipped, uids["iron_necklace"], _warrior)
	inventory = step["inventory"]
	equipped = step["equipped"]
	_eq("necklace goes to the accessory slot", equipped["accessory"]["item_id"], "iron_necklace")

	# A third ring replaces ring_1 and the old one goes back to the bag.
	var extra_ring := Inventory.add(inventory, "iron_ring", 1)
	inventory = extra_ring["inventory"]
	var extra_uid: String = inventory[inventory.size() - 1]["uid"]
	step = Equipment.equip(inventory, equipped, extra_uid, _warrior)
	_eq("third ring: ok", step["ok"], true)
	_eq("...replaced the first ring", step["replaced"]["uid"], uids["iron_ring"])
	inventory = step["inventory"]
	equipped = step["equipped"]
	_eq("...old ring is back in the bag", Inventory.find_uid(inventory, uids["iron_ring"]) >= 0, true)
	_eq("...new ring is worn", equipped["ring_1"]["uid"], extra_uid)
	_eq("...no double bonus: defense still 149 (124 + necklace 25)", _warrior_stats(equipped)["def_power"], 149)

	# Wearing the same piece twice is impossible: it is no longer in the bag.
	var again := Equipment.equip(inventory, equipped, uids["wooden_sword"], _warrior)
	_eq("a worn piece cannot be equipped again", again["error"], "NOT_FOUND")

	# Mount only counts while riding.
	step = Equipment.equip(inventory, equipped, uids["shadow_steed_mount"], _warrior)
	inventory = step["inventory"]
	equipped = step["equipped"]
	_near("mount equipped but not riding: move_speed unchanged", _warrior_stats(equipped, false)["move_speed"], 7.06)
	_near("riding: move_speed 7.06 + 4", _warrior_stats(equipped, true)["move_speed"], 11.06)

	# Unequip restores the base value.
	var worn_before := equipped.size()
	step = Equipment.unequip(inventory, equipped, "weapon")
	_eq("unequip weapon: ok", step["ok"], true)
	inventory = step["inventory"]
	equipped = step["equipped"]
	_eq("...one piece fewer worn", equipped.size(), worn_before - 1)
	_eq("...atk_power back to 21", _warrior_stats(equipped)["atk_power"], 21)
	_eq("...nothing there to unequip again", Equipment.unequip(inventory, equipped, "weapon")["error"], "NOT_EQUIPPED")

	# Errors.
	var potion_bag := _bag_with(["healing_potion", "iron_sword"])
	_eq("a potion has no unique id, so it cannot be equipped",
			Equipment.equip(potion_bag["inventory"], {}, potion_bag["uids"]["healing_potion"], _warrior)["ok"], false)
	var wrong_slot := Equipment.equip(potion_bag["inventory"], {}, potion_bag["uids"]["iron_sword"], _warrior, "boots")
	_eq("a sword does not fit the boots slot", wrong_slot["error"], "INVALID_SLOT")
	_eq("slot options for a ring", Equipment.slot_options("iron_ring"), ["ring_1", "ring_2"])
	_eq("unknown uid fails", Equipment.equip([], {}, "nope", _warrior)["error"], "NOT_FOUND")

	var full: Array = []
	for i in Inventory.max_slots():
		full = Inventory.add(full, "iron_sword", 1)["inventory"]
	_eq("unequip into a full bag fails",
			Equipment.unequip(full, {"weapon": {"uid": "x", "item_id": "iron_sword"}}, "weapon")["error"], "INVENTORY_FULL")

	_eq("level requirement blocks low levels", Equipment.check_requirements(5, "warrior", 10, []), "LEVEL_TOO_LOW")
	_eq("level requirement allows enough level", Equipment.check_requirements(10, "warrior", 10, []), "")
	_eq("class requirement blocks other classes", Equipment.check_requirements(50, "mage", 1, ["warrior", "brawler"]), "WRONG_CLASS")
	_eq("class requirement allows listed classes", Equipment.check_requirements(50, "Brawler", 1, ["warrior", "brawler"]), "")
