class_name CombatProfile
extends RefCounted
## Describes the weapon a fighter attacks with, in the format DamageCalculator
## expects, read from the item data. No weapon means bare hands (empty profile).


static func for_character(character: Dictionary) -> Dictionary:
	var equipment: Dictionary = character.get("equipment", {})
	if not equipment.has("weapon"):
		return {}
	return for_weapon(str(equipment["weapon"].get("item_id", "")))


static func for_weapon(item_id: String) -> Dictionary:
	if not ItemDB.exists(item_id) or ItemDB.category(item_id) != "weapon":
		return {}
	var rules := DataRegistry.get_config("combat_rules")
	var profile := {}

	var damage := ItemDB.weapon_damage(item_id)
	if not damage.is_empty():
		profile["min"] = damage["min"]
		profile["max"] = damage["max"]

	var bonus_type := str(ItemDB.row(item_id).get("item_BType", ""))
	profile["stat"] = str(rules.get("weapon_damage_stat", {}).get(bonus_type, "atk_power"))

	var element := ItemDB.element_damage(item_id)
	if not element.is_empty():
		profile["element"] = element["element"]
		profile["element_amount"] = element["amount"]

	var on_hit := ItemDB.on_hit_status(item_id)
	if not on_hit.is_empty():
		profile["on_hit"] = {"effect": on_hit["effect"], "chance": to_fraction(float(on_hit["chance"]))}
	return profile


## The sheets mix 0.25 (a fraction) and 36 (a percent). Up to 1 counts as a
## fraction, anything above as a percent.
static func to_fraction(chance: float) -> float:
	return clampf(chance if chance <= 1.0 else chance / 100.0, 0.0, 1.0)
