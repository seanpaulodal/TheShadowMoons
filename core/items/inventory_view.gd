class_name InventoryView
extends RefCounted
## Sorting and filtering for the bag screen. Pure logic on top of the inventory
## list, so the screen only has to draw the result.

const CATEGORY_IDS: Array[String] = ["all", "weapons", "armor", "accessories", "consumables", "other"]
const CATEGORY_NAMES := {
	"all": "All", "weapons": "Weapons", "armor": "Armor", "accessories": "Accessories",
	"consumables": "Potions", "other": "Other",
}
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "elite", "legendary", "mythic"]
const SORT_MODES: Array[String] = ["type", "rarity", "name"]
const SORT_NAMES := {"type": "Sort: Type", "rarity": "Sort: Rarity", "name": "Sort: Name"}


## The tab an item belongs under.
static func category_of(item_id: String) -> String:
	match ItemDB.category(item_id):
		"weapon":
			return "weapons"
		"armor":
			return "armor"
		"accessory":
			return "accessories"
		"consumable":
			return "consumables"
	return "other"


## The bag entries to show for a tab and a search text:
## [{"index": position in the bag, "entry": the entry}, ...]
static func filter(inventory: Array, category: String, search: String) -> Array:
	var result: Array = []
	var needle := search.strip_edges().to_lower()
	for i in inventory.size():
		var entry: Dictionary = inventory[i]
		var item_id := str(entry.get("item_id", ""))
		if category != "all" and category_of(item_id) != category:
			continue
		if needle != "" and not ItemDB.display_name(item_id).to_lower().contains(needle):
			continue
		result.append({"index": i, "entry": entry})
	return result


## A new, ordered copy of the bag. mode: "type" (tab order, then best rarity
## first), "rarity" (best first) or "name".
static func sorted(inventory: Array, mode: String) -> Array:
	var result := inventory.duplicate(true)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _key(a, mode) < _key(b, mode))
	return result


static func _key(entry: Dictionary, mode: String) -> Array:
	var item_id := str(entry.get("item_id", ""))
	var item_name := ItemDB.display_name(item_id).to_lower()
	var rarity_rank := RARITY_ORDER.find(ItemDB.rarity(item_id).to_lower())
	var type_rank := CATEGORY_IDS.find(category_of(item_id))
	match mode:
		"rarity":
			return [-rarity_rank, type_rank, item_name, item_id]
		"name":
			return [item_name, item_id]
	return [type_rank, -rarity_rank, item_name, item_id]
