extends Node
## DEV ONLY. Checks that a character's stats come from its OWN build (class, level,
## allocated attribute points) plus everything it wears, and that enemy data is
## never touched. Run with F6 and read the Output panel (nothing is saved to the
## cloud: the test turns saving off).

var _passed: int = 0
var _failed: int = 0
var _changes: int = 0


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	Session.character_changed.connect(func() -> void: _changes += 1)
	_new_character()

	_test_base()
	await _test_attributes()
	await _test_equipment()
	await _test_mixing_build_and_gear()
	await _test_mount_and_pants()
	await _test_level_up()
	await _test_failed_save()
	await _test_player_follows_build()
	_test_enemy_data_untouched()

	Session.save_enabled = true
	Session.clear()
	print("[build] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float) -> void:
	_report(label, absf(got - expected) < 0.011, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[build] PASS  ", label)
	else:
		_failed += 1
		print("[build] FAIL  %s  (%s)" % [label, detail])


func _new_character() -> void:
	Session.character = {
		"name": "BuildTest", "class_id": "warrior", "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 10, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _stats() -> Dictionary:
	return Session.total_stats()


func _equip_new(item_id: String) -> Dictionary:
	var added := Session.add_item(item_id, 1)
	if not added["ok"]:
		return added
	var bag: Array = Session.character["inventory"]
	return Session.equip_item(str(bag[bag.size() - 1]["uid"]))


# ---------- tests ----------

func _test_base() -> void:
	print("[build] --- a new character, no gear ---")
	var result := _stats()
	_eq("stats are calculated", result["ok"], true)
	_eq("warrior base atk_power", result["stats"]["atk_power"], 21)
	_eq("warrior base max_health", result["stats"]["max_health"], 134)
	var no_bonus := true
	for stat in result["equipment_bonus"]:
		if absf(float(result["equipment_bonus"][stat])) > 0.001:
			no_bonus = false
	_report("no gear means no equipment bonus", no_bonus)
	_eq("all 8 attributes exist (older characters get zeros)", Session.character["attributes"].size(), 8)


func _test_attributes() -> void:
	print("[build] --- the character's own attribute points ---")
	var before := _changes
	var spent := Session.allocate_attribute("str", 4)
	_eq("spend 4 points on STR", spent["ok"], true)
	_eq("...STR is 4", Session.character["attributes"]["str"], 4)
	_eq("...6 points left", Session.character["stat_points"], 6)
	_eq("...atk_power 21 + 4 x 2", _stats()["stats"]["atk_power"], 29)
	_eq("...that comes from the build, not from gear", _stats()["equipment_bonus"]["atk_power"], 0.0)
	_eq("...the screen is told once", _changes - before, 1)

	var too_many := Session.allocate_attribute("vit", 7)
	_eq("spending more than you have fails", too_many["error"], "NOT_ENOUGH_POINTS")
	_eq("...and changes nothing", Session.character["stat_points"], 6)
	_eq("unknown attribute fails", (Session.allocate_attribute("magic", 1))["error"], "UNKNOWN_ATTRIBUTE")


func _test_equipment() -> void:
	print("[build] --- weapon ---")
	var equipped := await _equip_new("wooden_sword")
	_eq("equip the wooden sword", equipped["ok"], true)
	var result := _stats()
	_eq("atk_power 29 + 15", result["stats"]["atk_power"], 44)
	_eq("the sword adds exactly 15", result["equipment_bonus"]["atk_power"], 15.0)
	_near("the sword adds 5 crit chance", result["equipment_bonus"]["crit_chance"], 5.0)
	_near("the sword adds 25 crit damage", result["equipment_bonus"]["crit_damage"], 25.0)
	_eq("base stats still include the attribute points", result["base_stats"]["atk_power"], 29)

	var consistent := true
	for stat in result["stats"]:
		if absf(float(result["stats"][stat]) - float(result["base_stats"][stat]) - float(result["equipment_bonus"][stat])) > 0.011:
			consistent = false
	_report("for every stat: final = base + equipment bonus", consistent)


func _test_mixing_build_and_gear() -> void:
	print("[build] --- armor set, jewelry, and attribute points together ---")
	for item_id in ["iron_armor", "iron_helm", "iron_gloves", "iron_boots"]:
		await _equip_new(item_id)
	_eq("defense: 12 base + 87 from armor, helmet, gloves, boots", _stats()["stats"]["def_power"], 99)

	await _equip_new("iron_ring")
	await _equip_new("ring_of_vigor")
	await _equip_new("iron_necklace")
	var worn: Array = Session.character["equipment"].keys()
	worn.sort()
	_eq("everything is in its own slot", worn,
			["accessory", "armor", "boots", "gloves", "helmet", "ring_1", "ring_2", "weapon"])
	_eq("defense 99 + ring 25 + necklace 25", _stats()["stats"]["def_power"], 149)
	_eq("max_health 134 + ring of vigor 50", _stats()["stats"]["max_health"], 184)

	var spent := Session.allocate_attribute("vit", 5)
	_eq("spend 5 points on VIT", spent["ok"], true)
	_eq("defense gets +4 from VIT on top of the gear", _stats()["stats"]["def_power"], 153)
	_eq("max_health gets +40 from VIT on top of the gear", _stats()["stats"]["max_health"], 224)
	_eq("gear bonus is unchanged by spending points (87 + 25 + 25)", _stats()["equipment_bonus"]["def_power"], 137.0)

	var bag_before: int = Session.character["inventory"].size()
	var removed := Session.unequip_item("weapon")
	_eq("take the weapon off", removed["ok"], true)
	_eq("...the sword is back in the bag", Session.character["inventory"].size(), bag_before + 1)
	_eq("...atk_power is back to 29 (the build alone)", _stats()["stats"]["atk_power"], 29)
	_eq("...defense is unchanged", _stats()["stats"]["def_power"], 153)
	var again := Session.unequip_item("weapon")
	_eq("nothing left to take off", again["error"], "NOT_EQUIPPED")


func _test_mount_and_pants() -> void:
	print("[build] --- mount and pants ---")
	await _equip_new("shadow_steed_mount")
	var walking := Session.total_stats(false)
	var riding := Session.total_stats(true)
	_near("mount equipped but not riding: speed unchanged", walking["stats"]["move_speed"], 7.06)
	_near("riding: speed + 4", riding["stats"]["move_speed"], 11.06)

	if ItemDB.exists("iron_pants"):
		var before: float = _stats()["stats"]["def_power"]
		var worn := await _equip_new("iron_pants")
		_eq("pants can be worn", worn["ok"], true)
		_eq("pants go to the pants slot", Session.character["equipment"]["pants"]["item_id"], "iron_pants")
		_report("pants add to defense", _stats()["stats"]["def_power"] > before)
	else:
		print("[build] note  no pants item in the item sheet yet. Add one (item_type Armor, equip_slot pants) and this check runs by itself.")


func _test_level_up() -> void:
	print("[build] --- leveling ---")
	var before: int = _stats()["stats"]["max_health"]
	var points_before: int = Session.character["stat_points"]
	var result := Session.grant_exp(100)
	_eq("100 EXP at level 1 gives one level", result["levels_gained"], 1)
	_eq("level is 2", Session.character["level"], 2)
	_eq("5 new stat points", Session.character["stat_points"], points_before + 5)
	_eq("max_health grows with the level (+11 for a warrior)", _stats()["stats"]["max_health"], before + 11)


func _test_failed_save() -> void:
	print("[build] --- a failed save is never lost ---")
	Session.save_enabled = true     # not signed in, so the cloud save must fail
	var bag_before: int = Session.character["inventory"].size()
	var result := Session.add_item("healing_potion", 3)
	_eq("the change is applied at once", result["ok"], true)
	_eq("...it is in the bag", Inventory.count(Session.character["inventory"], "healing_potion") >= 3, true)
	_eq("...and waits to be saved", Session.has_unsaved_changes(), true)
	var flushed := await Session.flush()
	_eq("the cloud save fails (nobody is signed in)", flushed["ok"], false)
	_eq("...the change is still there", Inventory.count(Session.character["inventory"], "healing_potion") >= 3, true)
	_eq("...and still waiting for the next try", Session.has_unsaved_changes(), true)
	Session.save_enabled = false
	_eq("with saving off, the queue is cleared", (await Session.flush())["ok"], true)
	_eq("bag size grew by one stack", Session.character["inventory"].size(), bag_before + 1)


func _test_player_follows_build() -> void:
	print("[build] --- the walking player follows the build ---")
	var world: Node3D = load("res://maps/world_test.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: PlayerController = world.player
	_near("player speed matches the total stats", player.move_speed(), Session.total_stats(false)["stats"]["move_speed"])

	var speed_before := player.move_speed()
	Session.allocate_attribute("agi", 5)
	_near("spending 5 points on AGI speeds the player up by itself", player.move_speed(), speed_before + 0.1)

	player.set_mounted(true)
	_near("riding adds the mount's +4", player.move_speed(), speed_before + 0.1 + 4.0)
	player.set_mounted(false)
	_near("dismounting takes it away again", player.move_speed(), speed_before + 0.1)
	world.queue_free()


func _test_enemy_data_untouched() -> void:
	print("[build] --- enemy data ---")
	_eq("all 104 enemies are still there", DataRegistry.get_ids("enemies").size(), 104)
	var dummy := DataRegistry.get_enemy("training_dummy")
	_eq("training dummy level", dummy["enemy_level"], 999999)
	_eq("training dummy health", dummy["max_health"], 999999)
	var beast := DataRegistry.get_enemy("blackthorn_dreadbeast")
	_eq("blackthorn level", beast["enemy_level"], 275)
	_eq("blackthorn health", beast["max_health"], 380000)
	_eq("blackthorn attack", beast["atk_power"], 2850)
	_eq("blackthorn defense", beast["def_power"], 1650)
