class_name SkillDB
extends RefCounted
## Read-only access to the skill data (TSM_Skills.json, the skill trees, the
## ultimates and the special attacks), plus the maths for ranks and the text shown
## in the skill window. Nothing here changes anything.

const SLOT_NAMES := ["skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6", "skill_7", "skill_8"]


static func _rules() -> Dictionary:
	return DataRegistry.get_config("skill_rules")


static func exists(skill_id: String) -> bool:
	return not DataRegistry.get_ids("skills").is_empty() and not skill(skill_id).is_empty()


static func skill(skill_id: String) -> Dictionary:
	return DataRegistry._get_row("skills", skill_id)


## The class a skill belongs to, as a lower-case id ("Warrior" -> "warrior").
static func class_of(skill_id: String) -> String:
	return str(skill(skill_id).get("skill_class", "")).to_lower()


static func skill_name(skill_id: String) -> String:
	return str(skill(skill_id).get("skill_name", skill_id))


static func max_rank(skill_id: String) -> int:
	return int(skill(skill_id).get("skill_max_rank", 1))


static func point_cost(skill_id: String) -> int:
	return int(skill(skill_id).get("skill_point_cost", 0))


static func unlock_level(skill_id: String) -> int:
	return int(skill(skill_id).get("skill_unlock_level", 1))


static func prerequisites(skill_id: String) -> Array:
	return skill(skill_id).get("skill_prerequisites", [])


static func path_of(skill_id: String) -> String:
	return str(skill(skill_id).get("skill_path", ""))


## All skill ids of a class (lower-case class id), in path and path order.
static func skills_for_class(class_id: String) -> Array:
	var result: Array = []
	for path in paths_for_class(class_id):
		result.append_array(path["skill_ids"])
	return result


## The class's specialization paths in order: [{"path_id", "path_name", "skill_ids"}].
static func paths_for_class(class_id: String) -> Array:
	var result: Array = []
	for entry in DataRegistry.get_config("skill_trees").get("paths", []):
		if str(entry.get("class_id", "")).to_lower() == class_id.to_lower():
			result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("path_order", 0)) < int(b.get("path_order", 0)))
	return result


## The skill every character of this class starts with (the level 1 skill).
static func starter_skill(class_id: String) -> String:
	for skill_id in skills_for_class(class_id):
		if unlock_level(skill_id) <= 1 and prerequisites(skill_id).is_empty():
			return str(skill_id)
	return ""


## The class's ultimate and special attack ({} when there is none).
static func ultimate_for_class(class_id: String) -> Dictionary:
	return _ability_for(DataRegistry.get_ids("ultimates"), "ultimates", class_id)


static func special_for_class(class_id: String) -> Dictionary:
	return _ability_for(DataRegistry.get_ids("specials"), "specials", class_id)


static func _ability_for(ids: Array, table: String, class_id: String) -> Dictionary:
	for ability_id in ids:
		var row := DataRegistry._get_row(table, ability_id)
		if str(row.get("ability_class", "")).to_lower() == class_id.to_lower():
			return row
	return {}


## An ultimate or special attack by id.
static func ability(ability_id: String) -> Dictionary:
	var row := DataRegistry._get_row("ultimates", ability_id)
	return row if not row.is_empty() else DataRegistry._get_row("specials", ability_id)


static func resource_label(resource_type: String) -> String:
	return str(_rules().get("resource_labels", {}).get(resource_type, resource_type.capitalize()))


# ---------- ranks ----------

## Rank 1 is the baseline. Each further rank adds the skill's per-rank amounts.
static func damage_multiplier(skill_id: String, rank: int) -> float:
	var scaling: Dictionary = skill(skill_id).get("skill_rank_scaling", {})
	return 1.0 + float(scaling.get("damage_multiplier_per_rank", 0.0)) * float(maxi(rank, 1) - 1)


static func effect_multiplier(skill_id: String, rank: int) -> float:
	var scaling: Dictionary = skill(skill_id).get("skill_rank_scaling", {})
	return 1.0 + float(scaling.get("effectiveness_multiplier_per_rank", 0.0)) * float(maxi(rank, 1) - 1)


static func cooldown_at_rank(skill_id: String, rank: int) -> float:
	var scaling: Dictionary = skill(skill_id).get("skill_rank_scaling", {})
	var factor := 1.0 - float(scaling.get("cooldown_reduction_per_rank", 0.0)) * float(maxi(rank, 1) - 1)
	return float(skill(skill_id).get("skill_cooldown_seconds", 0.0)) * maxf(0.1, factor)


static func cost_at_rank(skill_id: String, rank: int) -> float:
	var resource: Dictionary = skill(skill_id).get("skill_resource", {})
	return float(resource.get("cost", 0.0)) + float(resource.get("cost_per_rank", 0.0)) * float(maxi(rank, 1) - 1)


## Base damage of the skill at a rank (before the attribute part).
static func base_damage_at_rank(skill_id: String, rank: int) -> float:
	return float(skill(skill_id).get("skill_damage", {}).get("base_damage", 0.0)) * damage_multiplier(skill_id, rank)


# ---------- text for the skill window ----------

## What the skill does at a rank, as lines: [{"text": String, "kind": "info" | "damage" | "effect"}].
static func describe(skill_id: String, rank: int) -> Array:
	var data := skill(skill_id)
	if data.is_empty():
		return [{"text": "Unknown skill", "kind": "info"}]
	var lines: Array = []
	rank = maxi(rank, 1)

	var resource: Dictionary = data.get("skill_resource", {})
	lines.append({"text": "Cost: %s %s" % [_trim(cost_at_rank(skill_id, rank)), resource_label(str(resource.get("resource_type", "")))], "kind": "info"})
	lines.append({"text": "Cooldown: %s s    Cast: %s s" % [_trim(cooldown_at_rank(skill_id, rank)), _trim(float(data.get("skill_cast_time_seconds", 0.0)))], "kind": "info"})
	var range_text := "Range: %s m" % _trim(float(data.get("skill_range_meters", 0.0)))
	if float(data.get("skill_area_radius_meters", 0.0)) > 0.0:
		range_text += "    Area: %s m" % _trim(float(data["skill_area_radius_meters"]))
	var max_targets := int(data.get("skill_targeting", {}).get("max_targets", 1))
	if max_targets > 1:
		range_text += "    Up to %d targets" % max_targets
	lines.append({"text": range_text, "kind": "info"})

	var damage: Dictionary = data.get("skill_damage", {})
	var base := base_damage_at_rank(skill_id, rank)
	if base > 0.0:
		lines.append({"text": "Damage: %s + %s x %s  (%s)" % [_trim(base),
				_trim(float(damage.get("attribute_scaling", 0.0)) * damage_multiplier(skill_id, rank)),
				str(damage.get("scaling_attribute", "")), str(damage.get("damage_type", "")).capitalize()], "kind": "damage"})

	var effect: Dictionary = data.get("skill_effect", {})
	var power := effect_multiplier(skill_id, rank)
	match str(effect.get("effect_type", "")):
		"direct_damage":
			if int(effect.get("hit_count", 1)) > 1:
				lines.append({"text": "Hits %d times" % int(effect["hit_count"]), "kind": "effect"})
		"execute":
			lines.append({"text": "+%s%% damage to enemies below %s%% health" % [_trim(float(effect.get("bonus_damage_vs_low_hp_percent", 0.0)) * power * 100.0), _trim(float(effect.get("execute_threshold_target_hp_percent", 0.0)))], "kind": "effect"})
		"buff":
			var modifiers: Dictionary = effect.get("stat_modifiers", {})
			for key in modifiers:
				lines.append({"text": "%s +%s%% for %s s" % [str(key).replace("_percent", "").replace("_", " ").capitalize(), _trim(float(modifiers[key]) * power * 100.0), _trim(float(effect.get("duration_seconds", 0.0)))], "kind": "effect"})
		"defense":
			lines.append({"text": "Absorbs %s%% of damage for %s s" % [_trim(float(effect.get("damage_absorption_percent", 0.0)) * power * 100.0), _trim(float(effect.get("duration_seconds", 0.0)))], "kind": "effect"})
		"crowd_control":
			lines.append({"text": "Crowd control for %s s  (strength %s%%)" % [_trim(float(effect.get("duration_seconds", 0.0))), _trim(float(effect.get("control_strength", 0.0)) * power * 100.0)], "kind": "effect"})
		"damage_over_time":
			lines.append({"text": "Damage over %s s: %s%% of base damage every %s s" % [_trim(float(effect.get("duration_seconds", 0.0))), _trim(float(effect.get("damage_per_tick_percent_of_base", 0.0)) * power * 100.0), _trim(float(effect.get("tick_interval_seconds", 1.0)))], "kind": "effect"})
		"movement":
			lines.append({"text": "Moves you %s m" % _trim(float(effect.get("distance_meters", 0.0))), "kind": "effect"})
		"healing":
			lines.append({"text": "Heals %s%% of maximum health" % _trim(float(effect.get("heal_percent_max_hp", 0.0)) * power * 100.0), "kind": "effect"})
		"summon":
			lines.append({"text": "Summons %s (up to %d) for %s s, at %s%% attack power" % [str(effect.get("summon_id", "")).capitalize().replace("_", " "), int(effect.get("max_active_summons", 1)), _trim(float(effect.get("duration_seconds", 0.0))), _trim(float(effect.get("summon_attack_power_percent", 0.0)) * power * 100.0)], "kind": "effect"})
	return lines


## The lines for an ultimate or special attack.
static func describe_ability(ability_id: String, rank: int) -> Array:
	var data := ability(ability_id)
	if data.is_empty():
		return [{"text": "Unknown ability", "kind": "info"}]
	var lines: Array = []
	var cost: Dictionary = data.get("resource_cost", {})
	lines.append({"text": "Cost: %s %s" % [_trim(float(cost.get("cost", 0.0))), resource_label(str(cost.get("resource_type", "")))], "kind": "info"})
	var scaling: Dictionary = data.get("rank_scaling", {})
	var cooldown := float(data.get("cooldown_seconds", 0.0)) * maxf(0.1, 1.0 - float(scaling.get("cooldown_reduction_per_rank", 0.0)) * float(maxi(rank, 1) - 1))
	lines.append({"text": "Cooldown: %s s    Cast: %s s    Range: %s m" % [_trim(cooldown), _trim(float(data.get("cast_time_seconds", 0.0))), _trim(float(data.get("range_meters", 0.0)))], "kind": "info"})
	var damage: Dictionary = data.get("damage", {})
	var power := 1.0 + float(scaling.get("effectiveness_per_rank", 0.0)) * float(maxi(rank, 1) - 1)
	var base := float(damage.get("base_damage", data.get("effect", {}).get("base_damage", 0.0))) * power
	if base > 0.0:
		lines.append({"text": "Damage: %s + %s x %s  (%s)" % [_trim(base), _trim(float(damage.get("attribute_scaling", 0.0)) * power), str(damage.get("scaling_attribute", "")), str(damage.get("damage_type", "")).capitalize()], "kind": "damage"})
	lines.append({"text": str(data.get("description", "")), "kind": "info"})
	return lines


## "12", "8.6" - no needless decimals.
static func _trim(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.1))


# ---------- data check ----------

## {"errors": [...], "warnings": [...]}
static func validate() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var class_ids: Array = DataRegistry.get_ids("classes")
	var seen_paths := {}
	for skill_id in DataRegistry.get_ids("skills"):
		var data := skill(skill_id)
		if not class_ids.has(str(data.get("skill_class", "")).to_lower()):
			errors.append("%s: class '%s' is not a class" % [skill_id, str(data.get("skill_class", ""))])
		for prerequisite in data.get("skill_prerequisites", []):
			if not exists(str(prerequisite)):
				errors.append("%s: prerequisite %s does not exist" % [skill_id, str(prerequisite)])
		if int(data.get("skill_max_rank", 0)) < 1:
			errors.append("%s: max rank is below 1" % skill_id)
		if not str(data.get("skill_description", "")).is_empty() and "focused on" in str(data["skill_description"]):
			seen_paths["generic_descriptions"] = int(seen_paths.get("generic_descriptions", 0)) + 1
	for class_id in class_ids:
		if starter_skill(str(class_id)) == "":
			errors.append("class %s has no level 1 skill" % str(class_id))
		if ultimate_for_class(str(class_id)).is_empty():
			warnings.append("class %s has no ultimate" % str(class_id))
		if special_for_class(str(class_id)).is_empty():
			warnings.append("class %s has no special attack" % str(class_id))
		var in_paths := {}
		for path in paths_for_class(str(class_id)):
			for skill_id in path["skill_ids"]:
				if not exists(str(skill_id)):
					errors.append("path %s lists %s which does not exist" % [str(path["path_id"]), str(skill_id)])
				in_paths[str(skill_id)] = true
		for skill_id in DataRegistry.get_ids("skills"):
			if class_of(str(skill_id)) == str(class_id) and not in_paths.has(str(skill_id)):
				errors.append("%s is in no skill path" % str(skill_id))
	if seen_paths.has("generic_descriptions"):
		warnings.append("%d skills still have the placeholder description" % int(seen_paths["generic_descriptions"]))
	return {"errors": errors, "warnings": warnings}
