class_name AbilityEffects
extends RefCounted
## The numbers of an ultimate or a special attack, read from its data: damage,
## cost, cooldown and strength at a rank, and what kind of ability it is.
## (What each one does is in AbilityRunner.)


static func data(ability_id: String) -> Dictionary:
	return SkillDB.ability(ability_id)


static func effect(ability_id: String) -> Dictionary:
	return data(ability_id).get("effect", {})


## "waves", "execute_strike", "transform"... (set per ability in TSM_Skill_Rules.json).
static func behavior(ability_id: String) -> String:
	return str(DataRegistry.get_config("skill_rules").get("ability_behaviors", {}).get(ability_id, ""))


static func is_ultimate(ability_id: String) -> bool:
	return str(data(ability_id).get("ability_type", "")) == "ultimate"


static func needs_target(ability_id: String) -> bool:
	return (DataRegistry.get_config("skill_rules").get("ability_needs_target", []) as Array).has(behavior(ability_id))


static func requires_full_resource(ability_id: String) -> bool:
	return bool(effect(ability_id).get("requires_full_resource", false))


## Strength at a rank: 1.0 at rank 1, more with every rank.
static func power(ability_id: String, rank: int) -> float:
	var scaling: Dictionary = data(ability_id).get("rank_scaling", {})
	return 1.0 + float(scaling.get("effectiveness_per_rank", 0.0)) * float(maxi(rank, 1) - 1)


static func cooldown_at_rank(ability_id: String, rank: int) -> float:
	var scaling: Dictionary = data(ability_id).get("rank_scaling", {})
	var factor := 1.0 - float(scaling.get("cooldown_reduction_per_rank", 0.0)) * float(maxi(rank, 1) - 1)
	return float(data(ability_id).get("cooldown_seconds", 0.0)) * maxf(0.1, factor)


static func extra_cost(ability_id: String) -> int:
	return int(effect(ability_id).get("extra_mp_cost", 0))


## What it costs from the class bar (including any extra the ability asks for).
static func cost(ability_id: String) -> int:
	return roundi(float(data(ability_id).get("resource_cost", {}).get("cost", 0.0))) + extra_cost(ability_id)


static func range_meters(ability_id: String) -> float:
	return float(data(ability_id).get("range_meters", 8.0))


static func damage_type(ability_id: String) -> String:
	return str(data(ability_id).get("damage", {}).get("damage_type", "physical")).to_lower()


## (base + attribute x scaling) x strength at the rank. `base` is the listed damage
## (0 for abilities that only buff or heal).
static func raw_damage(ability_id: String, rank: int, attributes: Dictionary, base_override: float = -1.0) -> float:
	var damage: Dictionary = data(ability_id).get("damage", {})
	var base := base_override if base_override >= 0.0 else float(damage.get("base_damage", 0.0))
	var attribute := float(attributes.get(str(damage.get("scaling_attribute", "")).to_lower(), 0))
	return (base + attribute * float(damage.get("attribute_scaling", 0.0))) * power(ability_id, rank)
