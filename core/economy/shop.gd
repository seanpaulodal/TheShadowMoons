class_name Shop
extends RefCounted
## Buying and selling. Pure logic: every function takes the gold and the bag and
## returns the new gold and bag (or a failure), so nothing changes until the
## caller keeps the result. The shops themselves are in TSM_Shop_Rules.json.


static func shop_ids() -> Array:
	var ids: Array = []
	for shop in DataRegistry.get_config("shop_rules").get("shops", []):
		ids.append(str(shop["id"]))
	return ids


static func shop_def(shop_id: String) -> Dictionary:
	for shop in DataRegistry.get_config("shop_rules").get("shops", []):
		if str(shop["id"]) == shop_id:
			return shop
	return {}


## Everything a shop sells: every item of its categories that has a buy price,
## cheapest first.
static func stock(shop_id: String) -> Array:
	var categories: Array = shop_def(shop_id).get("categories", [])
	var items: Array = []
	for item_id in DataRegistry.get_ids("items"):
		if categories.has(ItemDB.category(item_id)) and buy_price(item_id) > 0:
			items.append(item_id)
	items.sort_custom(func(a: String, b: String) -> bool:
		if buy_price(a) != buy_price(b):
			return buy_price(a) < buy_price(b)
		return ItemDB.display_name(a) < ItemDB.display_name(b))
	return items


static func buy_price(item_id: String) -> int:
	return ItemDB.buy_price(item_id)


## What the shop pays: the sheet's sell value, but never more than max_sell_ratio
## of the buy price (the sheet has items that sell for more than they cost).
static func sell_price(item_id: String) -> int:
	var sheet := ItemDB.sell_price(item_id)
	var cost := ItemDB.buy_price(item_id)
	if cost > 0:
		var ratio := float(DataRegistry.get_config("shop_rules").get("max_sell_ratio", 0.5))
		return mini(sheet, int(floor(float(cost) * ratio)))
	return sheet


## Returns {"ok": true, "gold", "inventory", "cost"} or {"ok": false, "error", "message"}.
static func buy(gold: int, inventory: Array, item_id: String, qty: int = 1) -> Dictionary:
	if not ItemDB.exists(item_id):
		return _fail("UNKNOWN_ITEM", "Unknown item.")
	if qty < 1:
		return _fail("INVALID_AMOUNT", "Amount must be at least 1.")
	var price := buy_price(item_id)
	if price <= 0:
		return _fail("NOT_FOR_SALE", "That is not for sale.")
	var cost := price * qty
	if gold < cost:
		return _fail("NOT_ENOUGH_GOLD", "Not enough gold (need %s)." % StatDisplay.format_number(cost))
	var added := Inventory.add(inventory, item_id, qty)
	if not added["ok"]:
		return added
	return {"ok": true, "gold": gold - cost, "inventory": added["inventory"], "cost": cost}


## Sells from the bag. Gear is sold by its unique id (one piece); a stack by item id.
## Returns {"ok": true, "gold", "inventory", "earned"} or a failure.
static func sell(gold: int, inventory: Array, item_id: String, qty: int = 1, uid: String = "") -> Dictionary:
	if not ItemDB.exists(item_id):
		return _fail("UNKNOWN_ITEM", "Unknown item.")
	var price := sell_price(item_id)
	if price <= 0:
		return _fail("NOT_SELLABLE", "The shop won't buy that.")
	if qty < 1:
		return _fail("INVALID_AMOUNT", "Amount must be at least 1.")

	var removed: Dictionary
	var sold := qty
	if uid != "":
		removed = Inventory.remove_uid(inventory, uid)
		sold = 1
	else:
		removed = Inventory.remove(inventory, item_id, qty)
	if not removed["ok"]:
		return removed
	return {"ok": true, "gold": gold + price * sold, "inventory": removed["inventory"], "earned": price * sold}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
