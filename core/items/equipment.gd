class_name Equipment
extends RefCounted
## What the character wears. Pure logic like Inventory: nothing is changed in
## place, every function returns new inventory / equipped dictionaries.
##
## equipped = {"weapon": {"uid": "...", "item_id": "iron_sword"}, "ring_1": {...}, ...}
## Equipping moves the piece out of the bag into its slot, and the piece that was
## there goes back into the bag, so the same item can never be counted twice.


static func slots() -> Array:
	return DataRegistry.get_config("item_rules").get("equipment_slots", [])


## The character slots an item can go into: a ring fits ring_1 or ring_2.
static func slot_options(item_id: String) -> Array:
	var item_slot := ItemDB.equip_slot(item_id)
	if item_slot == "":
		return []
	var aliases: Dictionary = DataRegistry.get_config("item_rules").get("slot_aliases", {})
	if aliases.has(item_slot):
		return aliases[item_slot].duplicate()
	return [item_slot]


## Level and class check. Returns "" when allowed, otherwise an error code.
static func check_requirements(character_level: int, class_id: String,
		level_req: int, class_req: Array) -> String:
	if character_level < level_req:
		return "LEVEL_TOO_LOW"
	if not class_req.is_empty() and not class_req.has(class_id.to_lower()):
		return "WRONG_CLASS"
	return ""


## character = {"level": int, "class_id": String}
## target_slot is optional (use it to choose ring_2 for example).
## Returns {"ok": true, "inventory", "equipped", "replaced": entry or {}} or a failure.
static func equip(inventory: Array, equipped: Dictionary, uid: String, character: Dictionary,
		target_slot: String = "") -> Dictionary:
	var removed := Inventory.remove_uid(inventory, uid)
	if not removed["ok"]:
		return removed
	var entry: Dictionary = removed["entry"]
	var item_id := str(entry.get("item_id", ""))

	var options := slot_options(item_id)
	if options.is_empty():
		return _fail("NOT_EQUIPPABLE", "%s cannot be equipped." % ItemDB.display_name(item_id))

	var problem := check_requirements(int(character.get("level", 1)), str(character.get("class_id", "")),
			ItemDB.level_req(item_id), ItemDB.class_req(item_id))
	if problem == "LEVEL_TOO_LOW":
		return _fail(problem, "You need level %d to use this." % ItemDB.level_req(item_id))
	if problem == "WRONG_CLASS":
		return _fail(problem, "Your class cannot use this item.")

	var slot := target_slot
	if slot == "":
		slot = str(options[0])
		for option in options:
			if not equipped.has(option):
				slot = str(option)
				break
	elif not options.has(slot):
		return _fail("INVALID_SLOT", "That item does not fit the %s slot." % slot)

	var new_inventory: Array = removed["inventory"]
	var new_equipped := equipped.duplicate(true)
	var replaced: Dictionary = {}
	if new_equipped.has(slot):
		replaced = new_equipped[slot]
		new_inventory.append(replaced)    # a slot was just freed, so this always fits
	new_equipped[slot] = entry
	return {"ok": true, "inventory": new_inventory, "equipped": new_equipped, "replaced": replaced}


## Takes the piece off and puts it back in the bag (fails if the bag is full).
static func unequip(inventory: Array, equipped: Dictionary, slot: String) -> Dictionary:
	if not equipped.has(slot):
		return _fail("NOT_EQUIPPED", "Nothing is equipped there.")
	if inventory.size() >= Inventory.max_slots():
		return _fail("INVENTORY_FULL", "Your bag is full.")
	var new_equipped := equipped.duplicate(true)
	var entry: Dictionary = new_equipped[slot]
	new_equipped.erase(slot)
	var new_inventory := inventory.duplicate(true)
	new_inventory.append(entry)
	return {"ok": true, "inventory": new_inventory, "equipped": new_equipped}


## All stat bonuses from the worn gear, ready for StatCalculator.calculate().
## A mount only gives its bonus while the player is actually riding it.
static func modifiers(equipped: Dictionary, mounted: bool = false) -> Array:
	var result: Array = []
	for slot in equipped:
		if slot == "mount" and not mounted:
			continue
		for modifier in ItemDB.stat_modifiers(str(equipped[slot].get("item_id", ""))):
			result.append(modifier)
	return result


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
