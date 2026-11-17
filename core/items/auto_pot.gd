class_name AutoPot
extends RefCounted
## Decides which potions to drink by themselves. Pure logic: it looks at health
## and mana, the thresholds the player chose, the bag and the cooldowns, and
## answers with the potions to use. The player then uses them through the normal
## potion path, so all the usual rules (cooldowns, counts) still apply.

## The settings every new character starts with (Auto Pots off).
static func default_settings() -> Dictionary:
	var rules: Dictionary = DataRegistry.get_config("consumable_rules").get("auto_pot", {})
	return {
		"auto_hp": false,
		"auto_mp": false,
		"hp_percent": int(rules.get("default_hp_percent", 50)),
		"mp_percent": int(rules.get("default_mp_percent", 30)),
		"quick_slots": {"health": "", "mana": "", "stamina": ""},
	}


## state = {"hp", "max_hp", "mp", "max_mp", "settings", "inventory", "cooldowns": PotionCooldowns}
## Returns [{"item_id": String, "resource": "health" | "mana"}]: at most one per resource.
static func choose(state: Dictionary) -> Array:
	var settings: Dictionary = state["settings"]
	var inventory: Array = state["inventory"]
	var cooldowns: PotionCooldowns = state["cooldowns"]
	var quick: Dictionary = settings.get("quick_slots", {})
	var result: Array = []

	for entry in [
		["health", "auto_hp", "hp_percent", "hp", "max_hp"],
		["mana", "auto_mp", "mp_percent", "mp", "max_mp"],
	]:
		var resource: String = entry[0]
		if not settings.get(entry[1], false):
			continue
		var maximum := int(state[entry[4]])
		var current := int(state[entry[3]])
		if maximum <= 0 or current <= 0 or current >= maximum:
			continue
		if float(current) / float(maximum) * 100.0 > float(settings.get(entry[2], 50)):
			continue

		var missing := maximum - current
		var chosen := ""
		var assigned := str(quick.get(resource, ""))
		if assigned != "" and _usable(assigned, resource, inventory, cooldowns):
			chosen = assigned
		else:
			chosen = pick_potion(resource, missing, inventory, cooldowns)
		if chosen != "":
			result.append({"item_id": chosen, "resource": resource})
	return result


## The best potion in the bag for the missing amount: the smallest one that fills
## it, or the biggest one if none is big enough. Potions on cooldown are skipped.
static func pick_potion(resource: String, missing: int, inventory: Array, cooldowns: PotionCooldowns) -> String:
	var best := ""
	var best_amount := 0
	var seen := {}
	for entry in inventory:
		var item_id := str(entry.get("item_id", ""))
		if seen.has(item_id):
			continue
		seen[item_id] = true
		if not _usable(item_id, resource, inventory, cooldowns):
			continue
		var amount := int(ItemDB.consumable_effect(item_id)["amount"])
		if best == "":
			best = item_id
			best_amount = amount
		elif best_amount < missing and amount > best_amount:
			best = item_id
			best_amount = amount
		elif amount >= missing and (best_amount < missing or amount < best_amount):
			best = item_id
			best_amount = amount
	return best


static func _usable(item_id: String, resource: String, inventory: Array, cooldowns: PotionCooldowns) -> bool:
	var effect := ItemDB.consumable_effect(item_id)
	if effect.is_empty() or str(effect["resource"]) != resource:
		return false
	return Inventory.count(inventory, item_id) > 0 and cooldowns.is_ready(item_id)
