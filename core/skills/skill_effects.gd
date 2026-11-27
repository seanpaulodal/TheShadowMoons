class_name SkillEffects
extends RefCounted
## What a skill does, worked out from its data: the damage, and the status effects
## it puts on you or on enemies (buffs, shields, slows, damage over time...). Pure
## maths with no scenes. The data leaves some details to the game ("the exact stat
## application is handled by the combat effect resolver"), so how tags turn into
## effects is set in TSM_Skill_Rules.json.


static func _rules() -> Dictionary:
	return DataRegistry.get_config("skill_rules")


static func tags(skill_id: String) -> Array:
	return SkillDB.skill(skill_id).get("skill_tags", [])


static func effect(skill_id: String) -> Dictionary:
	return SkillDB.skill(skill_id).get("skill_effect", {})


static func effect_type(skill_id: String) -> String:
	return str(effect(skill_id).get("effect_type", ""))


# ---------- damage ----------

static func attribute_key(skill_id: String) -> String:
	return str(SkillDB.skill(skill_id).get("skill_damage", {}).get("scaling_attribute", "")).to_lower()


static func damage_type(skill_id: String) -> String:
	return str(SkillDB.skill(skill_id).get("skill_damage", {}).get("damage_type", "physical")).to_lower()


static func crit_bonus(skill_id: String) -> float:
	return float(SkillDB.skill(skill_id).get("skill_damage", {}).get("critical_bonus_percent", 0.0))


static func has_damage(skill_id: String) -> bool:
	return float(SkillDB.skill(skill_id).get("skill_damage", {}).get("base_damage", 0.0)) > 0.0


## (base + attribute x scaling) x rank multiplier. `attributes` is the character's
## attribute totals ({"str": 20, ...}).
static func raw_damage(skill_id: String, rank: int, attributes: Dictionary) -> float:
	var damage: Dictionary = SkillDB.skill(skill_id).get("skill_damage", {})
	var attribute := float(attributes.get(attribute_key(skill_id), 0))
	return (float(damage.get("base_damage", 0.0)) + attribute * float(damage.get("attribute_scaling", 0.0))) \
			* SkillDB.damage_multiplier(skill_id, rank)


static func hit_count(skill_id: String) -> int:
	return maxi(1, int(effect(skill_id).get("hit_count", 1)))


## 1.0, or more for an execute skill when the target's health is low enough.
static func execute_multiplier(skill_id: String, rank: int, target_hp_share: float) -> float:
	if effect_type(skill_id) != "execute":
		return 1.0
	var data := effect(skill_id)
	if target_hp_share * 100.0 > float(data.get("execute_threshold_target_hp_percent", 0.0)):
		return 1.0
	return 1.0 + float(data.get("bonus_damage_vs_low_hp_percent", 0.0)) * SkillDB.effect_multiplier(skill_id, rank)


## Buffs (attack power...) make skills hit harder: the share by which a fighter's
## current power is above its power without status effects (1.0 = none).
static func power_multiplier(fighter: Combatant) -> float:
	var best := 1.0
	for stat in ["atk_power", "magic_power"]:
		var base := float(fighter.base_stats.get(stat, 0.0))
		if base > 0.0:
			best = maxf(best, float(fighter.stats.get(stat, base)) / base)
	return best


# ---------- who it needs ----------

## True for skills that need an enemy: damage, execute, crowd control, damage
## over time, and debuffs. Buffs, shields, heals and plain movement do not.
static func needs_enemy(skill_id: String) -> bool:
	if effect_type(skill_id) == "summon":
		return false                       # a summon is called wherever you stand
	if has_damage(skill_id):
		return true
	if ["direct_damage", "execute", "damage_over_time", "crowd_control"].has(effect_type(skill_id)):
		return true
	return effect_type(skill_id) == "buff" and buff_on_enemy(skill_id)


static func buff_rule(skill_id: String) -> Dictionary:
	var by_tag: Dictionary = _rules().get("buff_by_tag", {})
	for tag in tags(skill_id):
		if by_tag.has(str(tag)):
			return by_tag[str(tag)]
	return {"stats": ["atk_power"]}


static func buff_on_enemy(skill_id: String) -> bool:
	return bool(buff_rule(skill_id).get("on_enemy", false))


# ---------- status effects ----------

static func _id(skill_id: String) -> String:
	return "skill_%s" % skill_id


## A buff on you (or a debuff on an enemy): the stat changes, from the skill's percent.
static func buff_definition(skill_id: String, rank: int) -> Dictionary:
	var data := effect(skill_id)
	var rule := buff_rule(skill_id)
	var direction := -1.0 if rule.get("negative", false) else 1.0
	var percent := 0.0
	for key in data.get("stat_modifiers", {}):
		percent = maxf(percent, float(data["stat_modifiers"][key]))
	percent *= 100.0 * SkillDB.effect_multiplier(skill_id, rank)
	var modifiers: Array = []
	for stat in rule.get("stats", ["atk_power"]):
		modifiers.append({"stat": str(stat), "flat": 0.0, "percent": percent * direction})
	return {"effect_id": _id(skill_id), "name": SkillDB.skill_name(skill_id), "kind": "debuff" if direction < 0.0 else "buff",
			"duration": float(data.get("duration_seconds", 10.0)), "stacking": "refresh", "max_stacks": 1,
			"cleansable": true, "modifiers": modifiers}


## A shield: you take that much less damage for a while.
static func defense_definition(skill_id: String, rank: int) -> Dictionary:
	var data := effect(skill_id)
	var absorbed := float(data.get("damage_absorption_percent", 0.0)) * 100.0 * SkillDB.effect_multiplier(skill_id, rank)
	return {"effect_id": _id(skill_id), "name": SkillDB.skill_name(skill_id), "kind": "buff",
			"duration": float(data.get("duration_seconds", 5.0)), "stacking": "refresh", "max_stacks": 1,
			"cleansable": false, "damage_taken_percent": -minf(absorbed, 90.0)}


## "root", "slow" or "silence" (from the skill's tags), or "".
static func cc_status(skill_id: String) -> String:
	var by_tag: Dictionary = _rules().get("cc_status_by_tag", {})
	for tag in tags(skill_id):
		if by_tag.has(str(tag)):
			return str(by_tag[str(tag)])
	return ""


## The crowd control put on an enemy: the base effect (its flags), the skill's time,
## and for a slow the skill's strength as the percent of speed lost.
static func cc_definition(skill_id: String, rank: int) -> Dictionary:
	var data := effect(skill_id)
	var base := DataRegistry.get_status_effect(cc_status(skill_id)).duplicate(true)
	if base.is_empty():
		return {}
	base["effect_id"] = _id(skill_id)
	base["name"] = SkillDB.skill_name(skill_id)
	base["duration"] = float(data.get("duration_seconds", float(base.get("duration", 2.0))))
	base["stacking"] = "refresh"
	base["max_stacks"] = 1
	if cc_status(skill_id) == "slow":
		base["modifiers"] = [{"stat": "move_speed", "flat": 0.0,
				"percent": -minf(float(data.get("control_strength", 0.3)) * 100.0 * SkillDB.effect_multiplier(skill_id, rank), 90.0)}]
	return base


static func dot_element(skill_id: String) -> String:
	var by_tag: Dictionary = _rules().get("dot_element_by_tag", {})
	for tag in tags(skill_id):
		if by_tag.has(str(tag)):
			return str(by_tag[str(tag)])
	return "physical"


## Damage over time: every tick hits for a share of the skill's damage.
static func dot_definition(skill_id: String, rank: int, raw: float) -> Dictionary:
	var data := effect(skill_id)
	var per_tick := raw * float(data.get("damage_per_tick_percent_of_base", 0.0)) * SkillDB.effect_multiplier(skill_id, rank)
	return {"effect_id": _id(skill_id), "name": SkillDB.skill_name(skill_id), "kind": "dot",
			"duration": float(data.get("duration_seconds", 5.0)), "stacking": "refresh", "max_stacks": 1,
			"cleansable": true,
			"tick": {"interval": maxf(0.1, float(data.get("tick_interval_seconds", 1.0))), "flat": per_tick,
					"percent_max_health": 0.0, "element": dot_element(skill_id)}}


# ---------- healing and movement ----------

## Health given back by a heal skill (a share of maximum health).
static func heal_amount(skill_id: String, rank: int, max_health: int) -> int:
	var share := float(effect(skill_id).get("heal_percent_max_hp", 0.0)) * SkillDB.effect_multiplier(skill_id, rank)
	return maxi(1, int(round(float(max_health) * share)))


static func heal_over_time_seconds(skill_id: String) -> float:
	return float(effect(skill_id).get("heal_over_time_seconds", 0.0))


## A heal spread over time: the same total, given every second.
static func hot_definition(skill_id: String, total: int) -> Dictionary:
	var seconds := heal_over_time_seconds(skill_id)
	return {"effect_id": _id(skill_id), "name": SkillDB.skill_name(skill_id), "kind": "hot",
			"duration": seconds, "stacking": "refresh", "max_stacks": 1, "cleansable": false,
			"tick": {"interval": 1.0, "flat": float(total) / maxf(1.0, seconds), "percent_max_health": 0.0,
					"element": "holy", "heal": true}}


## "dash", "backstep" or "teleport_behind" (from the tags), or "".
static func movement_kind(skill_id: String) -> String:
	if effect_type(skill_id) != "movement":
		return ""
	var by_tag: Dictionary = _rules().get("movement_by_tag", {})
	for tag in tags(skill_id):
		if by_tag.has(str(tag)):
			return str(by_tag[str(tag)])
	return "dash"


static func movement_distance(skill_id: String) -> float:
	return float(effect(skill_id).get("distance_meters", 0.0))
