class_name Inventory
extends RefCounted
## The bag. Pure logic: every function takes the current inventory (an Array)
## and returns a NEW one, so nothing changes until the caller keeps the result.
##
## Entries:
##   stackable item  -> {"item_id": "healing_potion", "qty": 12}
##   gear (unique)   -> {"uid": "<unique id>", "item_id": "iron_sword"}
## One entry uses one slot. Stacks are limited by max_stack, the bag by max_slots
## (both set in TSM_Item_Rules.json). Adding is all or nothing.

static var _counter: int = 0


static func max_slots() -> int:
	return int(DataRegistry.get_config("item_rules").get("inventory", {}).get("max_slots", 60))


static func max_stack() -> int:
	return int(DataRegistry.get_config("item_rules").get("inventory", {}).get("max_stack", 999))


## A new unique id for a piece of gear.
static func new_uid() -> String:
	_counter += 1
	return "%d-%d-%d" % [Time.get_ticks_usec(), randi() % 1000000, _counter]


## Total amount of an item in the bag.
static func count(inventory: Array, item_id: String) -> int:
	var total := 0
	for entry in inventory:
		if str(entry.get("item_id", "")) == item_id:
			total += int(entry.get("qty", 1))
	return total


static func find_uid(inventory: Array, uid: String) -> int:
	for i in inventory.size():
		if str(inventory[i].get("uid", "")) == uid:
			return i
	return -1


static func free_slots(inventory: Array) -> int:
	return maxi(0, max_slots() - inventory.size())


## Adds `qty` of an item, or fails without changing anything.
## Returns {"ok": true, "inventory": Array} or {"ok": false, "error": CODE, "message": text}.
static func add(inventory: Array, item_id: String, qty: int = 1) -> Dictionary:
	if not ItemDB.exists(item_id):
		return _fail("UNKNOWN_ITEM", "Unknown item: %s" % item_id)
	if qty < 1:
		return _fail("INVALID_AMOUNT", "Amount must be at least 1.")

	var result := inventory.duplicate(true)

	if ItemDB.is_stackable(item_id):
		var remaining := qty
		var limit := max_stack()
		# Top up stacks that already exist.
		for entry in result:
			if remaining <= 0:
				break
			if str(entry.get("item_id", "")) != item_id:
				continue
			var room := limit - int(entry.get("qty", 1))
			if room > 0:
				var moved := mini(room, remaining)
				entry["qty"] = int(entry.get("qty", 1)) + moved
				remaining -= moved
		# Then start new stacks.
		while remaining > 0:
			if result.size() >= max_slots():
				return _fail("INVENTORY_FULL", "Your bag is full.")
			var moved := mini(limit, remaining)
			result.append({"item_id": item_id, "qty": moved})
			remaining -= moved
	else:
		if result.size() + qty > max_slots():
			return _fail("INVENTORY_FULL", "Your bag is full.")
		for i in qty:
			result.append({"uid": new_uid(), "item_id": item_id})

	return {"ok": true, "inventory": result}


## Removes `qty` of a stackable item (takes from the smallest stacks first),
## or removes gear by item id (the first matching pieces).
static func remove(inventory: Array, item_id: String, qty: int = 1) -> Dictionary:
	if qty < 1:
		return _fail("INVALID_AMOUNT", "Amount must be at least 1.")
	if count(inventory, item_id) < qty:
		return _fail("NOT_ENOUGH_ITEMS", "You don't have enough of that item.")

	var result := inventory.duplicate(true)
	var remaining := qty
	# Smallest stacks first, so stacks do not stay half empty.
	var indexes: Array = []
	for i in result.size():
		if str(result[i].get("item_id", "")) == item_id:
			indexes.append(i)
	indexes.sort_custom(func(a: int, b: int) -> bool:
		return int(result[a].get("qty", 1)) < int(result[b].get("qty", 1)))

	var to_delete: Array = []
	for i in indexes:
		if remaining <= 0:
			break
		var have := int(result[i].get("qty", 1))
		if have <= remaining:
			remaining -= have
			to_delete.append(i)
		else:
			result[i]["qty"] = have - remaining
			remaining = 0
	to_delete.sort()
	to_delete.reverse()
	for i in to_delete:
		result.remove_at(i)
	return {"ok": true, "inventory": result}


## Removes one specific piece of gear. Returns the removed entry too.
static func remove_uid(inventory: Array, uid: String) -> Dictionary:
	var index := find_uid(inventory, uid)
	if index < 0:
		return _fail("NOT_FOUND", "That item is not in your bag.")
	var result := inventory.duplicate(true)
	var entry: Dictionary = result[index]
	result.remove_at(index)
	return {"ok": true, "inventory": result, "entry": entry}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
