class_name LootTable
extends RefCounted
## What one kill of one enemy gives: EXP, gold and items. It only READS the
## enemy sheet (xp_reward, gold_min, gold_max, PTN_dropchance, MNA_dropchance)
## and the item sheet (dropped_by_enemy, drop_chance). Nothing is changed.
##
## Returns {"exp": int, "gold": int, "items": [{"item_id", "qty"}]}.
## `rolls` replaces random numbers (for tests): "gold" (0..1), "drop:<item_id>"
## and "potion:health" / "potion:mana" (0..1), or "all" for every roll at once.

static var _shared_rng: RandomNumberGenerator


static func roll(enemy_id: String, rolls: Dictionary = {}, rng: RandomNumberGenerator = null) -> Dictionary:
	var row := DataRegistry.get_enemy(enemy_id)
	if row.is_empty():
		return {"exp": 0, "gold": 0, "items": []}
	var generator := rng if rng != null else _get_rng()

	var gold_low := int(_number(row.get("gold_min")))
	var gold_high := maxi(gold_low, int(_number(row.get("gold_max"))))
	var gold := mini(gold_high, gold_low + int(floor(_roll(rolls, "gold", generator) * float(gold_high - gold_low + 1))))

	var items: Array = []

	# Items that list this enemy in the item sheet.
	var item_ids: Array = DataRegistry.get_ids("items")
	item_ids.sort()
	for item_id in item_ids:
		if not ItemDB.drop_sources(item_id).has(enemy_id):
			continue
		var chance := CombatProfile.to_fraction(ItemDB.drop_chance(item_id))
		if chance > 0.0 and _roll(rolls, "drop:%s" % item_id, generator) < chance:
			items.append({"item_id": item_id, "qty": 1})

	# A health and a mana potion, sized to the enemy's level.
	var level := int(_number(row.get("enemy_level")))
	for kind in ["health", "mana"]:
		var column := "PTN_dropchance" if kind == "health" else "MNA_dropchance"
		var chance := clampf(_number(row.get(column)), 0.0, 1.0)
		if chance > 0.0 and _roll(rolls, "potion:%s" % kind, generator) < chance:
			var potion := potion_for_level(kind, level)
			if potion != "" and ItemDB.exists(potion):
				items.append({"item_id": potion, "qty": 1})

	var cap := int(DataRegistry.get_config("loot_rules").get("max_item_drops_per_kill", 0))
	if cap > 0 and items.size() > cap:
		items.resize(cap)

	return {"exp": int(_number(row.get("xp_reward"))), "gold": gold, "items": items}


## The potion for an enemy level: the highest tier whose min level fits.
static func potion_for_level(kind: String, level: int) -> String:
	var tiers: Array = DataRegistry.get_config("loot_rules").get("potion_tiers", {}).get(kind, [])
	var chosen := ""
	for tier in tiers:
		if level >= int(tier[0]):
			chosen = str(tier[1])
	return chosen


static func _roll(rolls: Dictionary, key: String, generator: RandomNumberGenerator) -> float:
	if rolls.has(key):
		return float(rolls[key])
	if rolls.has("all"):
		return float(rolls["all"])
	return generator.randf()


static func _number(value: Variant) -> float:
	return ItemDB._number(value, 0.0)


static func _get_rng() -> RandomNumberGenerator:
	if _shared_rng == null:
		_shared_rng = RandomNumberGenerator.new()
		_shared_rng.randomize()
	return _shared_rng
