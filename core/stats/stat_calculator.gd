class_name StatCalculator
extends RefCounted
## Turns a character's class, level, spent attribute points and equipment/buff
## modifiers into final stats. Pure logic: it reads data from DataRegistry and
## never touches UI, scenes or the network.
##
## final = (class base + growth * (level - 1) + attribute points * coefficients
##          + flat modifiers) * (1 + percent modifiers / 100), then min/max limits.
##
## Modifier format (one entry per bonus):
##   {"stat": "atk_power", "flat": 10.0, "percent": 5.0, "source": "item:iron_sword"}
## "flat", "percent" and "source" are optional.

const ATTRIBUTES: Array[String] = ["str", "int", "vit", "dex", "wis", "lck", "agi", "cha"]


## Applies modifiers (same format as in calculate) to stats that are already
## calculated, for example a player's stats plus the current status effects, or an
## enemy's stats plus a Slow. Returns new stats; the input is not changed.
static func apply_modifiers(stats: Dictionary, modifiers: Array) -> Dictionary:
	var result := stats.duplicate()
	if modifiers.is_empty():
		return result
	var stat_defs: Dictionary = DataRegistry.get_config("stat_rules").get("stats", {})
	var flat := {}
	var percent := {}
	for modifier in modifiers:
		var stat := str(modifier.get("stat", ""))
		flat[stat] = float(flat.get(stat, 0.0)) + float(modifier.get("flat", 0.0))
		percent[stat] = float(percent.get(stat, 0.0)) + float(modifier.get("percent", 0.0))
	for stat in flat:
		if not stats.has(stat):
			continue
		var value := (float(stats[stat]) + float(flat[stat])) * (1.0 + float(percent[stat]) / 100.0)
		var stat_def: Dictionary = stat_defs.get(stat, {})
		if stat_def.has("min"):
			value = maxf(value, float(stat_def["min"]))
		if stat_def.has("max"):
			value = minf(value, float(stat_def["max"]))
		if stat_def.get("integer", false) or stats[stat] is int:
			result[stat] = int(floor(value))
		else:
			result[stat] = snappedf(value, 0.01)
	return result


## Start attributes of the class plus the points the player has spent.
static func attribute_totals(class_id: String, allocated: Dictionary) -> Dictionary:
	var class_data := DataRegistry.get_class_data(class_id)
	var start: Dictionary = class_data.get("start_attributes", {})
	var totals := {}
	for attribute in ATTRIBUTES:
		totals[attribute] = int(start.get(attribute, 0)) + int(allocated.get(attribute, 0))
	return totals


## Returns {"ok": true, "level": int, "attributes": {...}, "stats": {...},
## "ignored_modifiers": [...]} or {"ok": false, "error": CODE, "message": text}.
static func calculate(class_id: String, level: int, allocated: Dictionary = {},
		modifiers: Array = []) -> Dictionary:
	var class_data := DataRegistry.get_class_data(class_id)
	var rules := DataRegistry.get_config("stat_rules")
	var progression := DataRegistry.get_config("progression")
	if class_data.is_empty():
		return {"ok": false, "error": "UNKNOWN_CLASS", "message": "Unknown class: %s" % class_id}
	if rules.is_empty() or progression.is_empty():
		return {"ok": false, "error": "MISSING_DATA", "message": "Stat data is not loaded."}

	var lvl := clampi(level, 1, int(progression["max_level"]))
	var totals := attribute_totals(class_id, allocated)

	var stat_defs: Dictionary = rules["stats"]
	var attribute_defs: Dictionary = rules["attributes"]
	var base_defaults: Dictionary = rules["base_defaults"]
	var growth_defaults: Dictionary = rules["growth_defaults"]
	var base: Dictionary = class_data["base_stats"]
	var growth: Dictionary = class_data["growth_stats"]

	# Add up all modifiers per stat.
	var flat := {}
	var percent := {}
	var ignored: Array = []
	for modifier in modifiers:
		var stat := str(modifier.get("stat", ""))
		if not stat_defs.has(stat):
			ignored.append(stat)
			continue
		flat[stat] = float(flat.get(stat, 0.0)) + float(modifier.get("flat", 0.0))
		percent[stat] = float(percent.get(stat, 0.0)) + float(modifier.get("percent", 0.0))

	var stats := {}
	for stat in stat_defs:
		var value := float(base.get(stat, base_defaults.get(stat, 0.0)))
		value += float(growth.get(stat, growth_defaults.get(stat, 0.0))) * (lvl - 1)
		for attribute in ATTRIBUTES:
			var per_point: Dictionary = attribute_defs.get(attribute, {}).get("per_point", {})
			value += float(per_point.get(stat, 0.0)) * int(totals[attribute])
		value = (value + float(flat.get(stat, 0.0))) * (1.0 + float(percent.get(stat, 0.0)) / 100.0)

		var stat_def: Dictionary = stat_defs[stat]
		if stat_def.has("min"):
			value = maxf(value, float(stat_def["min"]))
		if stat_def.has("max"):
			value = minf(value, float(stat_def["max"]))

		if stat_def.get("integer", false):
			stats[stat] = int(floor(value))
		else:
			stats[stat] = snappedf(value, 0.01)

	return {
		"ok": true,
		"level": lvl,
		"attributes": totals,
		"stats": stats,
		"ignored_modifiers": ignored,
	}
