class_name Shop
extends RefCounted
## Buying and selling. Pure logic: every function takes the gold and the bag and
## returns the new gold and bag (or a failure), so nothing changes until the
## caller keeps the result. The shops themselves are in TSM_Shop_Rules.json.


## Stock lists are worked out once per shop (the sheet has hundreds of items).
static var _stock_cache: Dictionary = {}
static var _class_cache: Dictionary = {}


## Forget the saved lists (the data was loaded again).
static func clear_cache() -> void:
	_stock_cache.clear()
	_class_cache.clear()


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
	if _stock_cache.has(shop_id):
		return _stock_cache[shop_id]
	var categories: Array = shop_def(shop_id).get("categories", [])
	var keyed: Array = []                         # [price, name, id], sorted without re-reading the data
	for item_id in DataRegistry.get_ids("items"):
		if categories.has(ItemDB.category(item_id)) and buy_price(item_id) > 0:
			keyed.append([buy_price(item_id), ItemDB.display_name(item_id), str(item_id)])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	var items: Array = []
	for entry in keyed:
		items.append(entry[2])
	_stock_cache[shop_id] = items
	return items


## The shop's stock that this class can use (items for every class or for this one).
static func stock_for_class(shop_id: String, class_id: String) -> Array:
	var key := "%s|%s" % [shop_id, class_id.to_lower()]
	if _class_cache.has(key):
		return _class_cache[key]
	var result: Array = []
	for item_id in stock(shop_id):
		var classes := ItemDB.class_req(item_id)
		if classes.is_empty() or classes.has(class_id.to_lower()):
			result.append(item_id)
	_class_cache[key] = result
	return result


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
