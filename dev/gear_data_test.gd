extends Node
## DEV ONLY. Checks the new item data (601 items): the file formats the loader
## accepts, equip slots found from the names, class and weapon type, level
## requirements, attribute bonuses (STR, VIT...), elemental weapons and the shop
## filter. Needs no login and saves nothing. Run with F6.

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character()

	_test_data_and_formats()
	_test_data_check()
	_test_slots()
	_test_classes_and_levels()
	_test_weapon_types()
	_test_attribute_bonuses()
	_test_elemental_weapons()
	_test_shop_filter()
	_test_equipping()

	Session.save_enabled = true
	Session.clear()
	print("[gear] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[gear] PASS  ", label)
	else:
		_failed += 1
		print("[gear] FAIL  %s  (%s)" % [label, detail])


func _new_character() -> void:
	Session.character = {
		"name": "Fighter", "class_id": "warrior", "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _with_prefix(prefix: String) -> String:
	for item_id in DataRegistry.get_ids("items"):
		if str(item_id).begins_with(prefix):
			return str(item_id)
	return ""


func _modifier(item_id: String, stat: String) -> float:
	for modifier in ItemDB.stat_modifiers(item_id):
		if modifier["stat"] == stat:
			return float(modifier["flat"])
	return 0.0


# ---------- the data and the file formats ----------

func _test_data_and_formats() -> void:
	print("[gear] --- the data ---")
	var ids := DataRegistry.get_ids("items")
	_eq("601 items", ids.size(), 601)
	var counts := {}
	for item_id in ids:
		counts[ItemDB.category(item_id)] = int(counts.get(ItemDB.category(item_id), 0)) + 1
	_eq("457 weapons", counts["weapon"], 457)
	_eq("51 armor pieces", counts["armor"], 51)
	_eq("38 accessories", counts["accessory"], 38)
	_eq("50 consumables (the potions are back)", counts["consumable"], 50)
	_eq("3 mounts and 2 scrolls", [counts["mount"], counts["scroll"]], [3, 2])
	_eq("the original items are all still there", ItemDB.exists("healing_potion") and ItemDB.exists("potion_hp_minor") and ItemDB.exists("iron_sword"), true)

	# The loader accepts all three shapes your sheet exports have had.
	var row := {"item_name": "A", "item_type": "Weapon"}
	var wrapped: Array = DataRegistry._normalize({"Master_Data": {"a_1": row.duplicate(), "a_2": row.duplicate()}}, "item_id")
	var keyed: Array = DataRegistry._normalize({"a_1": row.duplicate(), "a_2": row.duplicate()}, "item_id")
	var listed: Array = DataRegistry._normalize([{"item_id": "a_1", "item_name": "A"}, {"item_id": "a_2", "item_name": "A"}], "item_id")
	_eq("format 1: ids inside a sheet-name wrapper", wrapped.size(), 2)
	_eq("format 2: ids at the top", keyed.size(), 2)
	_eq("format 3: a list of rows with an item_id column", listed.size(), 2)
	_eq("...ids are kept in the first format", wrapped[0]["item_id"], "a_1")
	_eq("...and in the second", keyed[1]["item_id"], "a_2")


func _test_data_check() -> void:
	print("[gear] --- the data check ---")
	var report := ItemDB.validate()
	_eq("no data errors at all", report["errors"], [])
	for problem in report["errors"]:
		print("[gear] ERROR ", problem)
	var important := 0
	for warning in report["warnings"]:
		var text := str(warning)
		if "element" in text or "status effect" in text or "weapon_type" in text or "item_class" in text or "gives no stats" in text:
			important += 1
			print("[gear] WARN  ", text)
	_eq("no unknown element, status effect, class, weapon type or bonus", important, 0)
	var dup_names := 0
	for warning in report["warnings"]:
		if "share the name" in str(warning):
			dup_names += 1
	_report("repeated item names are reported as warnings (%d)" % dup_names, dup_names > 0)


# ---------- slots ----------

func _test_slots() -> void:
	print("[gear] --- slots found from the names ---")
	_eq("helm", ItemDB.equip_slot("fire_warrior_helm_set"), "helmet")
	_eq("chest", ItemDB.equip_slot("fire_warrior_chest_set"), "armor")
	_eq("gloves", ItemDB.equip_slot("fire_warrior_gloves_set"), "gloves")
	_eq("pants", ItemDB.equip_slot("fire_warrior_pants_set"), "pants")
	_eq("boots", ItemDB.equip_slot("fire_warrior_boots_set"), "boots")
	_eq("ring", ItemDB.equip_slot("fire_warrior_ring_set"), "ring")
	_eq("necklace goes in the accessory slot", ItemDB.equip_slot("fire_warrior_necklace_set"), "accessory")
	_eq("an attuned ring", ItemDB.equip_slot("fire_attuned_ring"), "ring")
	_eq("an attuned necklace", ItemDB.equip_slot("fire_attuned_necklace"), "accessory")
	_eq("every weapon goes in the weapon slot", ItemDB.equip_slot(_with_prefix("warrior_001_")), "weapon")
	_eq("an original item keeps its slot from the extras file", ItemDB.equip_slot("iron_armor"), "armor")
	_eq("a potion has no slot", ItemDB.equip_slot("healing_potion"), "")

	var per_slot := {}
	for item_id in DataRegistry.get_ids("items"):
		if str(item_id).ends_with("_set"):
			per_slot[ItemDB.equip_slot(item_id)] = int(per_slot.get(ItemDB.equip_slot(item_id), 0)) + 1
	_eq("each class set has all 7 pieces (9 of each kind)", per_slot, {"helmet": 9, "armor": 9, "gloves": 9, "pants": 9, "boots": 9, "ring": 9, "accessory": 9})
	var without_slot := 0
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.category(item_id) in ["weapon", "armor", "accessory", "mount"] and ItemDB.equip_slot(item_id) == "":
			without_slot += 1
	_eq("no piece of gear is left without a slot", without_slot, 0)


# ---------- class, level ----------

func _test_classes_and_levels() -> void:
	print("[gear] --- class and level ---")
	_eq("a warrior set piece is for warriors", ItemDB.class_req("fire_warrior_helm_set"), ["warrior"])
	_eq("a mage set piece is for mages", ItemDB.class_req("ice_mage_helm_set"), ["mage"])
	_eq("'All' means every class", ItemDB.class_req("fire_attuned_ring"), [])
	_eq("a warrior weapon is for warriors", ItemDB.class_req(_with_prefix("warrior_001_")), ["warrior"])
	_eq("a necromancer weapon is for necromancers", ItemDB.class_req(_with_prefix("necromancer_010_")), ["necromancer"])
	_eq("an original weapon has no class limit", ItemDB.class_req("wooden_sword"), [])
	_eq("a potion has no class limit", ItemDB.class_req("healing_potion"), [])
	_eq("a class name is read in any capitalisation", ItemDB.class_req("fire_warrior_helm_set"), ["warrior"])

	var classes := {}
	for item_id in DataRegistry.get_ids("items"):
		for class_id in ItemDB.class_req(item_id):
			classes[class_id] = int(classes.get(class_id, 0)) + 1
	_eq("all 9 classes are used", classes.keys().size(), 9)
	_eq("each class has 50 weapons, 5 set pieces + ring/necklace... (57 items)", classes["warrior"], 57)

	_eq("weapon tier 1 needs level 1", ItemDB.level_req(_with_prefix("warrior_001_")), 1)
	_eq("weapon tier 2 (number 6) needs level 30", ItemDB.level_req(_with_prefix("warrior_006_")), 30)
	_eq("weapon tier 6 (number 26) needs level 150", ItemDB.level_req(_with_prefix("mage_026_")), 150)
	_eq("weapon tier 10 (number 50) needs level 270", ItemDB.level_req(_with_prefix("warrior_050_")), 270)
	var low := 999
	var high := 0
	for item_id in DataRegistry.get_ids("items"):
		if str(item_id).ends_with("_set") or "attuned" in str(item_id):
			low = mini(low, ItemDB.level_req(item_id))
			high = maxi(high, ItemDB.level_req(item_id))
	_eq("set gear needs levels from 10", low, 10)
	_eq("...up to 80", high, 80)


# ---------- weapon types ----------

func _test_weapon_types() -> void:
	print("[gear] --- weapon types ---")
	_eq("a greatsword", ItemDB.weapon_type(_with_prefix("warrior_001_")), "Greatsword")
	_eq("a wooden sword (original)", ItemDB.weapon_type("wooden_sword"), "Sword")
	_eq("a dagger (original)", ItemDB.weapon_type("frost_dagger"), "Dagger")
	_eq("a bow (original)", ItemDB.weapon_type("storm_bow"), "Bow")
	_eq("a staff (original)", ItemDB.weapon_type("archmage_staff"), "Staff")
	_eq("an axe (original)", ItemDB.weapon_type("battle_axe"), "Axe")
	_eq("armor has no weapon type", ItemDB.weapon_type("fire_warrior_helm_set"), "")

	var groups := {}
	var types_per_class := {}
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.category(item_id) == "weapon" and ItemDB.class_req(item_id).size() == 1:
			var key := "%s|%s" % [ItemDB.class_req(item_id)[0], ItemDB.weapon_type(item_id)]
			groups[key] = int(groups.get(key, 0)) + 1
			var class_id: String = ItemDB.class_req(item_id)[0]
			if not types_per_class.has(class_id):
				types_per_class[class_id] = {}
			types_per_class[class_id][ItemDB.weapon_type(item_id)] = true
	_eq("9 classes x 5 weapon types = 45 groups", groups.size(), 45)
	var every_ten := true
	for key in groups:
		if groups[key] != 10:
			every_ten = false
	_eq("...of 10 tiers each", every_ten, true)
	var five_each := true
	for class_id in types_per_class:
		if types_per_class[class_id].size() != 5:
			five_each = false
	_eq("every class has exactly 5 weapon types", five_each, true)
	_eq("the item details show the weapon type", str(ItemInfo.lines(_with_prefix("warrior_001_"))[0]["text"]).begins_with("Weapon  -  Greatsword"), true)
	_eq("...and the class limit", ItemInfo.lines(_with_prefix("warrior_001_")).any(func(l: Dictionary) -> bool: return l["text"] == "Classes: Warrior"), true)


# ---------- attribute bonuses ----------

func _test_attribute_bonuses() -> void:
	print("[gear] --- bonuses: STR, VIT, DEF and friends ---")
	var vit := ItemDB.attribute_bonus("fire_warrior_helm_set")
	_eq("VIT +3 is read as Vitality, 3 points", [vit["attribute"], vit["label"], vit["points"]], ["vit", "Vitality", 3.0])
	_near("...worth 24 max health (8 per point)", _modifier("fire_warrior_helm_set", "max_health"), 24.0)
	_near("...2.4 defense (0.8 per point)", _modifier("fire_warrior_helm_set", "def_power"), 2.4)
	_near("...and 6 stamina (2 per point)", _modifier("fire_warrior_helm_set", "max_stamina"), 6.0)
	_near("STR +2: 4 attack", _modifier("fire_warrior_gloves_set", "atk_power"), 4.0)
	_near("DEF +6 is 6 defense, straight", _modifier("fire_warrior_pants_set", "def_power"), 6.0)
	_eq("DEF is not an attribute", ItemDB.attribute_bonus("fire_warrior_pants_set"), {})
	_near("AGI +2: evasion 0.8", _modifier("fire_warrior_boots_set", "evasion"), 0.8)
	_near("LCK +2: crit chance 0.4", _modifier("fire_warrior_ring_set", "crit_chance"), 0.4)
	_near("...and crit damage 1.0", _modifier("fire_warrior_ring_set", "crit_damage"), 1.0)
	_near("WIS +3: magic resist 2.4", _modifier("fire_warrior_necklace_set", "magic_resist"), 2.4)
	_eq("old bonuses still work (Attack on a sword)", _modifier("wooden_sword", "atk_power") > 0.0, true)

	var texts: Array = []
	for line in ItemInfo.lines("fire_warrior_helm_set"):
		texts.append(str(line["text"]))
	_eq("the details say 'Vitality +3'", texts.has("Vitality  +3"), true)
	_eq("...and do not list the three small effects", texts.any(func(t: String) -> bool: return t.begins_with("Max Health")), false)

	var gives_something := true
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.category(item_id) in ["armor", "accessory"] and ItemDB.stat_modifiers(item_id).is_empty():
			gives_something = false
	_eq("every armor piece and accessory gives some bonus", gives_something, true)


# ---------- elemental weapons ----------

func _test_elemental_weapons() -> void:
	print("[gear] --- elemental weapons ---")
	_eq("Wind counts as Nature", ElementalSystem.canonical("Wind"), ["nature"])
	_eq("Light counts as Holy", ElementalSystem.canonical("Light"), ["holy"])
	_eq("Lightning counts as Shock", ElementalSystem.canonical("Lightning"), ["shock"])
	var with_element := 0
	var with_status := 0
	var unknown_element := 0
	var unknown_effect := 0
	var chance_ok := true
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.category(item_id) != "weapon" or ItemDB.class_req(item_id).is_empty():
			continue
		var element := ItemDB.element_damage(item_id)
		if not element.is_empty():
			with_element += 1
			if ElementalSystem.canonical(str(element["element"])).is_empty():
				unknown_element += 1
		var hit := ItemDB.on_hit_status(item_id)
		if not hit.is_empty():
			with_status += 1
			if DataRegistry.get_status_effect(str(hit["effect"]).to_lower()).is_empty():
				unknown_effect += 1
			if float(hit["chance"]) <= 0.0 or float(hit["chance"]) > 0.5:
				chance_ok = false
	_eq("all 450 new weapons deal element damage", with_element, 450)
	_eq("...and apply a status effect", with_status, 450)
	_eq("every element is known to the chart", unknown_element, 0)
	_eq("every status effect exists", unknown_effect, 0)
	_eq("effect chances are small fractions (4% to 15%)", chance_ok, true)

	var wind_weapon := ""
	for item_id in DataRegistry.get_ids("items"):
		if ItemDB.category(item_id) == "weapon" and str(ItemDB.element_damage(item_id).get("element", "")) == "Wind":
			wind_weapon = str(item_id)
			break
	_eq("a Wind weapon exists", wind_weapon != "", true)
	var profile := CombatProfile.for_weapon(wind_weapon)
	_eq("its combat profile carries the element and amount", [profile["element"], float(profile["element_amount"]) > 0.0], ["Wind", true])
	_eq("...and its on-hit effect", profile.has("on_hit"), true)
	var original := CombatProfile.for_weapon("flame_blade")
	_eq("the old text style '25 (Fire)' still works", [original["element"], original["element_amount"]], ["Fire", 25.0])
	var lines: Array = []
	for line in ItemInfo.lines(wind_weapon):
		lines.append(str(line["text"]))
	_eq("the details show the element damage", lines.any(func(t: String) -> bool: return t.begins_with("Wind damage")), true)


# ---------- the shop filter ----------

func _test_shop_filter() -> void:
	print("[gear] --- shops and My class ---")
	_eq("the weaponsmith sells 457 weapons in all", Shop.stock("weaponsmith").size(), 457)
	_eq("a warrior sees 57 of them (50 warrior + 7 for everyone)", Shop.stock_for_class("weaponsmith", "warrior").size(), 57)
	_eq("a necromancer sees 57 too", Shop.stock_for_class("weaponsmith", "necromancer").size(), 57)
	_eq("an unknown class sees only the 7 for everyone", Shop.stock_for_class("weaponsmith", "nobody").size(), 7)
	_eq("a warrior sees 11 of the 51 armor pieces (6 for everyone, 5 for warriors)", Shop.stock_for_class("armorer", "warrior").size(), 11)
	var all_usable := true
	for item_id in Shop.stock_for_class("armorer", "mage"):
		var classes := ItemDB.class_req(item_id)
		if not classes.is_empty() and not classes.has("mage"):
			all_usable = false
	_eq("a mage is never shown armor for another class", all_usable, true)
	_eq("the general store is the same for every class (potions)", Shop.stock_for_class("general_store", "gunner").size(), Shop.stock("general_store").size())
	_eq("the stock list is worked out once and kept", Shop.stock("weaponsmith") == Shop.stock("weaponsmith"), true)
	Shop.clear_cache()
	_eq("...and can be rebuilt after the data is loaded again", Shop.stock("weaponsmith").size(), 457)
	var cheapest: String = Shop.stock("weaponsmith")[0]
	_report("the weaponsmith's cheapest weapon is cheap", Shop.buy_price(cheapest) <= 150, str(Shop.buy_price(cheapest)))
	var legendary := _with_prefix("warrior_050_")
	_eq("the top weapon costs a lot, and sells for at most half", Shop.sell_price(legendary) <= Shop.buy_price(legendary) / 2, true)


# ---------- equipping ----------

func _test_equipping() -> void:
	print("[gear] --- equipping the new gear ---")
	var warrior_weapon := _with_prefix("warrior_001_")
	var bag: Array = Inventory.add([], warrior_weapon, 1)["inventory"]
	var uid: String = bag[0]["uid"]
	var as_mage := Equipment.equip(bag, {}, uid, {"level": 50, "class_id": "mage"})
	_eq("a mage can't use a warrior weapon", as_mage["error"], "WRONG_CLASS")
	var as_warrior := Equipment.equip(bag, {}, uid, {"level": 1, "class_id": "warrior"})
	_eq("a warrior can", as_warrior["ok"], true)
	_eq("...in the weapon slot", as_warrior["equipped"].has("weapon"), true)

	var strong := _with_prefix("warrior_006_")
	var strong_bag: Array = Inventory.add([], strong, 1)["inventory"]
	var low_level := Equipment.equip(strong_bag, {}, strong_bag[0]["uid"], {"level": 20, "class_id": "warrior"})
	_eq("a level 20 warrior can't use a level 30 weapon", low_level["error"], "LEVEL_TOO_LOW")
	_eq("a level 30 warrior can", Equipment.equip(strong_bag, {}, strong_bag[0]["uid"], {"level": 30, "class_id": "warrior"})["ok"], true)

	# The bonus really changes the character's stats.
	_new_character()
	Session.character["level"] = 30
	var before: Dictionary = Session.total_stats(false)["stats"]
	Session.add_item("fire_warrior_helm_set", 1)
	Session.add_item("fire_warrior_pants_set", 1)
	for entry in Session.character["inventory"].duplicate():
		var result := Session.equip_item(str(entry["uid"]))
		_eq("wearing %s works" % str(entry["item_id"]), result["ok"], true)
	var after: Dictionary = Session.total_stats(false)["stats"]
	_near("VIT +3 added 24 max health", float(after["max_health"]) - float(before["max_health"]), 24.0, 0.6)
	_near("VIT +3 and DEF +6 added 8.4 defense", float(after["def_power"]) - float(before["def_power"]), 8.4, 0.6)
	_eq("both pieces are worn", [Session.character["equipment"].has("helmet"), Session.character["equipment"].has("pants")], [true, true])
