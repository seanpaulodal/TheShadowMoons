class_name ItemDB
extends RefCounted
## Typed, safe access to item data. Everything that needs to know about an item
## (inventory, equipment, shop, combat) asks ItemDB instead of reading the raw
## item rows, so the messy parts of the sheet ("N/A", "NaN", numbers stored as
## text) are handled in exactly one place.

const ABSENT: Array[String] = ["", "N/A", "NaN", "nan", "null"]


# ---------- basic information ----------

static func exists(item_id: String) -> bool:
	return DataRegistry.has_item(item_id)


static func row(item_id: String) -> Dictionary:
	return DataRegistry.get_item(item_id)


static func display_name(item_id: String) -> String:
	return str(row(item_id).get("item_name", item_id))


static func description(item_id: String) -> String:
	return str(row(item_id).get("item_desc", ""))


static func rarity(item_id: String) -> String:
	return str(row(item_id).get("item_rarity", "Common"))


## Lower-case item type: consumable, weapon, armor, accessory, mount, scroll...
static func category(item_id: String) -> String:
	return str(row(item_id).get("item_type", "")).to_lower()


static func is_stackable(item_id: String) -> bool:
	var value: Variant = row(item_id).get("stackable", false)
	if value is bool:
		return value
	return str(value).to_lower() == "true"


static func buy_price(item_id: String) -> int:
	return int(_number(row(item_id).get("item_buy_value"), 0.0))


static func sell_price(item_id: String) -> int:
	return int(_number(row(item_id).get("item_sell_value"), 0.0))


static func icon_path(item_id: String) -> String:
	var path: Variant = row(item_id).get("item_iconpath")
	return "" if is_absent(path) else str(path)


# ---------- equipment ----------

## "weapon", "armor", "helmet", "gloves", "pants", "boots", "ring", "accessory",
## "mount", or "" when the item cannot be equipped. Order of trust: an equip_slot
## column in the item sheet, then TSM_Item_Extra.json, then a guess from the item's
## type (every weapon goes in the weapon slot) or from a word in its id (helm, chest,
## gloves, pants, boots, ring, necklace; see slot_keywords in TSM_Item_Rules.json).
static func equip_slot(item_id: String) -> String:
	var written := str(_from_sheet_or_extra(item_id, "equip_slot", ""))
	if written != "":
		return written
	return _guess_slot(item_id)


static func _guess_slot(item_id: String) -> String:
	var rules := DataRegistry.get_config("item_rules")
	var type_name := str(row(item_id).get("item_type", ""))
	var defaults: Dictionary = rules.get("slot_defaults", {})
	if defaults.has(type_name):
		return str(defaults[type_name])
	if not (rules.get("type_to_slots", {}) as Dictionary).has(type_name):
		return ""
	var words := item_id.to_lower().split("_", false)
	for pair in rules.get("slot_keywords", []):
		if words.has(str(pair[0])):
			return str(pair[1])
	return ""


static func level_req(item_id: String) -> int:
	return maxi(1, int(_number(_from_sheet_or_extra(item_id, "level_req", 1), 1.0)))


## Lower-case class ids that may use the item. Empty means every class.
static func class_req(item_id: String) -> Array:
	# The item_class column: a class name, several separated by commas, "All", or empty.
	var column: Variant = row(item_id).get("item_class")
	if not is_absent(column):
		var listed: Array = []
		for entry in str(column).split(","):
			var cleaned := entry.strip_edges().to_lower()
			if cleaned == "all":
				return []
			if cleaned != "":
				listed.append(cleaned)
		return listed
	var raw: Variant = _from_sheet_or_extra(item_id, "class_req", [])
	var result: Array = []
	if raw is Array:
		for entry in raw:
			result.append(str(entry).strip_edges().to_lower())
	elif not is_absent(raw):
		for entry in str(raw).split(","):
			var cleaned := entry.strip_edges().to_lower()
			if cleaned != "":
				result.append(cleaned)
	return result


## "Greatsword", "Longbow", "Dual Pistols"... or "" when the sheet does not say.
static func weapon_type(item_id: String) -> String:
	var raw: Variant = row(item_id).get("weapon_type")
	return "" if is_absent(raw) else str(raw).strip_edges()


## When the item's bonus is attribute points (STR, AGI, VIT, INT, DEX, WIS, LCK):
## {"attribute": "vit", "label": "Vitality", "points": 3.0}. Otherwise {}.
static func attribute_bonus(item_id: String) -> Dictionary:
	var item := row(item_id)
	var attributes: Dictionary = DataRegistry.get_config("item_rules").get("attribute_btypes", {})
	var key := str(item.get("item_BType", ""))
	if not attributes.has(key) or is_absent(item.get("item_BValue")):
		return {}
	var attribute := str(attributes[key])
	var definition: Dictionary = DataRegistry.get_config("stat_rules").get("attributes", {}).get(attribute, {})
	return {"attribute": attribute, "label": str(definition.get("label", attribute.capitalize())),
			"points": _number(item.get("item_BValue"), 0.0)}


## Bonuses this item gives while equipped, in the format StatCalculator expects:
## [{"stat": "atk_power", "flat": 15.0, "source": "item:wooden_sword"}, ...]
static func stat_modifiers(item_id: String) -> Array:
	var item := row(item_id)
	var rules := DataRegistry.get_config("item_rules")
	if item.is_empty() or rules.is_empty():
		return []

	var mods: Array = []
	var source := "item:%s" % item_id

	var stat := str(rules["btype_to_stat"].get(str(item.get("item_BType", "")), ""))
	if stat != "" and not is_absent(item.get("item_BValue")):
		mods.append({"stat": stat, "flat": _number(item.get("item_BValue"), 0.0), "source": source})

	# Attribute points (for example VIT +3) are worth what the same points are worth
	# when spent: each point adds its per-point amounts (stat_rules.json).
	var attribute := attribute_bonus(item_id)
	if not attribute.is_empty():
		var per_point: Dictionary = DataRegistry.get_config("stat_rules").get("attributes", {}).get(attribute["attribute"], {}).get("per_point", {})
		for stat_name in per_point:
			mods.append({"stat": str(stat_name), "flat": float(attribute["points"]) * float(per_point[stat_name]),
					"source": source, "attribute": attribute["attribute"]})

	if category(item_id) == "weapon":
		var conversion: Dictionary = rules.get("weapon_bonus_conversion", {})
		for column in conversion:
			var raw: Variant = item.get(column)
			if is_absent(raw):
				continue
			var setting: Dictionary = conversion[column]
			var value := (_number(raw, 0.0) + float(setting.get("offset", 0.0))) \
					* float(setting.get("scale", 1.0))
			mods.append({"stat": str(setting["stat"]), "flat": value, "source": source})
	return mods


# ---------- weapons (used by combat in M5) ----------

## {"min": int, "max": int}, or {} when the item has no damage range.
static func weapon_damage(item_id: String) -> Dictionary:
	var item := row(item_id)
	if category(item_id) != "weapon" or is_absent(item.get("dmg_min")) or is_absent(item.get("dmg_max")):
		return {}
	return {"min": int(_number(item.get("dmg_min"), 0.0)), "max": int(_number(item.get("dmg_max"), 0.0))}


## {"element": "Fire", "amount": 25.0}, or {} when the weapon has no element damage.
static func element_damage(item_id: String) -> Dictionary:
	var raw: Variant = row(item_id).get("elem_dmg")
	if is_absent(raw):
		return {}
	if not (raw is String):
		# Newer weapons: a number, with the element named in status_element.
		var amount := _number(raw, 0.0)
		var element_name: Variant = row(item_id).get("status_element")
		if amount <= 0.0 or is_absent(element_name):
			return {}
		return {"element": str(element_name).strip_edges(), "amount": amount}
	var regex := RegEx.new()
	regex.compile("^\\s*(\\d+(?:\\.\\d+)?)\\s*\\(\\s*([A-Za-z ]+?)\\s*\\)\\s*$")
	var found := regex.search(str(raw))
	if found == null:
		return {}
	return {"element": found.get_string(2), "amount": float(found.get_string(1))}


## {"element": "Fire", "effect": "Burn", "chance": 0.25}, or {} if the weapon
## applies no status effect when it hits.
static func on_hit_status(item_id: String) -> Dictionary:
	var item := row(item_id)
	if category(item_id) != "weapon" or is_absent(item.get("status_effect")):
		return {}
	var status := {"effect": str(item["status_effect"]).strip_edges(), "chance": _number(item.get("effect_chance"), 0.0)}
	status["element"] = "" if is_absent(item.get("status_element")) else str(item["status_element"])
	return status


# ---------- consumables ----------

## {"resource": "health" | "mana" | "stamina", "amount": int}, or {} if not restorative.
static func consumable_effect(item_id: String) -> Dictionary:
	var item := row(item_id)
	var rules := DataRegistry.get_config("item_rules")
	if category(item_id) != "consumable" or rules.is_empty():
		return {}
	var resource := str(rules["consumable_btype"].get(str(item.get("item_BType", "")), ""))
	if resource == "" or is_absent(item.get("item_BValue")):
		return {}
	return {"resource": resource, "amount": int(_number(item.get("item_BValue"), 0.0))}


# ---------- where items come from ----------

## Enemy ids that can drop the item.
static func drop_sources(item_id: String) -> Array:
	var raw: Variant = row(item_id).get("dropped_by_enemy")
	var result: Array = []
	if is_absent(raw):
		return result
	for entry in str(raw).split(","):
		var cleaned := entry.strip_edges()
		if cleaned != "":
			result.append(cleaned)
	return result


static func drop_chance(item_id: String) -> float:
	return _number(row(item_id).get("drop_chance"), 0.0)


## Shops that sell the item. In the current sheet, vendor names sit in the
## status_effect column of armor, accessories and mounts.
static func vendors(item_id: String) -> Array:
	var rules := DataRegistry.get_config("item_rules")
	var known: Array = rules.get("known_vendors", [])
	var result: Array = []
	if category(item_id) == "weapon":
		return result
	for entry in str(row(item_id).get("status_effect", "")).split(","):
		var cleaned := entry.strip_edges()
		if known.has(cleaned):
			result.append(cleaned)
	return result


# ---------- data health check ----------

## Looks for problems in the item data. Returns {"errors": [...], "warnings": [...]}.
## Errors break features (for example gear with no slot). Warnings are odd but harmless.
static func validate() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var rules := DataRegistry.get_config("item_rules")
	if rules.is_empty():
		return {"errors": ["item_rules is not loaded"], "warnings": []}

	var type_to_slots: Dictionary = rules.get("type_to_slots", {})
	var names := {}
	for item_id in DataRegistry.get_ids("items"):
		var item := row(item_id)
		var type_name := str(item.get("item_type", ""))
		var slot := equip_slot(item_id)

		if type_to_slots.has(type_name):
			if slot == "":
				errors.append("%s (%s) has no equip slot" % [item_id, type_name])
			elif not (type_to_slots[type_name] as Array).has(slot):
				errors.append("%s: slot '%s' is not allowed for type %s" % [item_id, slot, type_name])
		elif slot != "":
			warnings.append("%s (%s) has a slot but its type cannot be equipped" % [item_id, type_name])

		if type_name == "Consumable" and consumable_effect(item_id).is_empty():
			errors.append("%s: consumable with unknown or missing effect (%s)" % [item_id, str(item.get("item_BType"))])

		if type_to_slots.has(type_name) and stat_modifiers(item_id).is_empty():
			warnings.append("%s: gear that gives no stats (BType '%s')" % [item_id, str(item.get("item_BType"))])

		var elem: Variant = item.get("elem_dmg")
		if not is_absent(elem) and elem is String and element_damage(item_id).is_empty():
			warnings.append("%s: element damage '%s' cannot be read" % [item_id, str(elem)])

		var class_column: Variant = item.get("item_class")
		if not is_absent(class_column):
			for entry in str(class_column).split(","):
				var class_name_text := entry.strip_edges().to_lower()
				if class_name_text != "all" and class_name_text != "" and DataRegistry.get_class_data(class_name_text).is_empty():
					errors.append("%s: item_class '%s' is not a class" % [item_id, entry.strip_edges()])
		if type_name == "Weapon":
			if weapon_type(item_id) == "":
				warnings.append("%s: weapon has no weapon_type" % item_id)
			var damage_element := str(element_damage(item_id).get("element", ""))
			if damage_element != "" and ElementalSystem.canonical(damage_element).is_empty():
				warnings.append("%s: element '%s' is not in the element chart (counts as neutral)" % [item_id, damage_element])
			var effect_name := str(on_hit_status(item_id).get("effect", ""))
			if effect_name != "" and DataRegistry.get_status_effect(effect_name.to_lower().replace(" ", "_")).is_empty():
				warnings.append("%s: status effect '%s' does not exist" % [item_id, effect_name])

		for enemy_id in drop_sources(item_id):
			if DataRegistry.get_enemy(enemy_id).is_empty():
				warnings.append("%s: dropped by unknown enemy '%s'" % [item_id, enemy_id])

		if sell_price(item_id) > buy_price(item_id):
			warnings.append("%s: sells for more (%d) than it costs (%d)" % [item_id, sell_price(item_id), buy_price(item_id)])

		var icon := icon_path(item_id)
		if icon == "" or not ResourceLoader.exists(icon):
			warnings.append("%s: icon not found (%s)" % [item_id, icon])

		var item_name := display_name(item_id)
		if names.has(item_name):
			warnings.append("%s and %s share the name '%s'" % [names[item_name], item_id, item_name])
		else:
			names[item_name] = item_id

	return {"errors": errors, "warnings": warnings}


# ---------- helpers ----------

static func is_absent(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		return ABSENT.has((value as String).strip_edges())
	return false


static func _number(value: Variant, fallback: float) -> float:
	if is_absent(value):
		return fallback
	if value is int or value is float:
		return float(value)
	var text := str(value).strip_edges()
	return text.to_float() if text.is_valid_float() else fallback


static func _from_sheet_or_extra(item_id: String, column: String, fallback: Variant) -> Variant:
	var from_sheet: Variant = row(item_id).get(column)
	if not is_absent(from_sheet):
		return from_sheet
	var extra := DataRegistry.get_item_extra(item_id)
	if extra.has(column) and not is_absent(extra[column]):
		return extra[column]
	return fallback
