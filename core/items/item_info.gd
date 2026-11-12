class_name ItemInfo
extends RefCounted
## Turns an item into the lines shown in its details panel. It only reads the
## item data. Each line is {"text": String, "kind": String}; the screen colours
## the lines by kind: "title", "muted", "stat", "effect", "warning", "price".

const SLOT_LABELS := {
	"weapon": "Weapon", "armor": "Armor", "helmet": "Helmet", "gloves": "Gloves",
	"pants": "Pants", "boots": "Boots", "ring": "Ring", "ring_1": "Ring", "ring_2": "Ring",
	"accessory": "Accessory", "pet": "Pet", "mount": "Mount",
}
const RESOURCE_LABELS := {"health": "HP", "mana": "MP", "stamina": "SP"}


static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, slot.capitalize()))


static func lines(item_id: String) -> Array:
	var result: Array = []
	if not ItemDB.exists(item_id):
		return [{"text": "Unknown item", "kind": "warning"}]

	var slot := ItemDB.equip_slot(item_id)
	var type_text := ItemDB.category(item_id).capitalize()
	if slot != "":
		type_text += "  -  " + slot_label(slot)
	result.append({"text": "%s  |  %s" % [type_text, ItemDB.rarity(item_id)], "kind": "muted"})

	var description := ItemDB.description(item_id)
	if description != "" and not ItemDB.is_absent(description):
		result.append({"text": description, "kind": "muted"})

	var damage := ItemDB.weapon_damage(item_id)
	if not damage.is_empty():
		result.append({"text": "Damage  %d - %d" % [int(damage["min"]), int(damage["max"])], "kind": "stat"})

	for modifier in ItemDB.stat_modifiers(item_id):
		var stat := str(modifier["stat"])
		var text := "%s  %s" % [StatDisplay.stat_name(stat), StatDisplay.format_bonus(stat, modifier["flat"])]
		if ItemDB.category(item_id) == "mount":
			text += "  (while riding)"
		result.append({"text": text, "kind": "stat"})

	var element := ItemDB.element_damage(item_id)
	if not element.is_empty():
		result.append({"text": "%s damage  +%d" % [str(element["element"]), int(element["amount"])], "kind": "effect"})

	var on_hit: Dictionary = CombatProfile.for_weapon(item_id).get("on_hit", {})
	if not on_hit.is_empty():
		result.append({"text": "%d%% chance to inflict %s" % [roundi(float(on_hit["chance"]) * 100.0), str(on_hit["effect"])], "kind": "effect"})

	var use := ItemDB.consumable_effect(item_id)
	if not use.is_empty():
		result.append({"text": "Restores %s %s" % [StatDisplay.format_number(int(use["amount"])), RESOURCE_LABELS.get(use["resource"], "")], "kind": "effect"})

	if slot != "":
		if ItemDB.level_req(item_id) > 1:
			result.append({"text": "Requires level %d" % ItemDB.level_req(item_id), "kind": "warning"})
		var classes := ItemDB.class_req(item_id)
		if not classes.is_empty():
			var names: Array = []
			for class_id in classes:
				names.append(str(class_id).capitalize())
			result.append({"text": "Classes: %s" % ", ".join(names), "kind": "warning"})

	var buy := ItemDB.buy_price(item_id)
	var sell := ItemDB.sell_price(item_id)
	if buy > 0 or sell > 0:
		result.append({"text": "Buy %s    Sell %s" % [StatDisplay.format_number(buy), StatDisplay.format_number(sell)], "kind": "price"})
	return result
