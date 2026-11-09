class_name DamageCalculator
extends RefCounted
## Works out what one attack does. Pure math: it knows nothing about scenes,
## floating text or the UI, so damage never depends on how it is displayed.
##
## attacker = {"stats": {...}, "weapon": {...}, "skill_multiplier": 1.0}
##   weapon = {"min", "max", "stat" ("atk_power" or "magic_power"),
##             "element", "element_amount"}   (all optional; empty = bare hands)
## defender = {"stats": {...}, "profile": ElementalSystem profile, "damage_taken_multiplier": 1.0}
##
## Order: hit or miss -> parry -> crit and block rolls -> damage.
## `rolls` replaces the random numbers (for tests): "hit", "parry", "crit", "block"
## in 0..100, and "weapon" in 0..1. Anything missing is rolled randomly.
##
## Returns {"outcome": "hit" | "miss" | "parry", "damage": int, "physical": int,
## "elemental": int, "element": String, "element_multiplier": float,
## "is_crit": bool, "blocked": bool, "hit_chance": float}.

static var _shared_rng: RandomNumberGenerator


static func resolve(attacker: Dictionary, defender: Dictionary, rolls: Dictionary = {},
		rng: RandomNumberGenerator = null) -> Dictionary:
	var rules := DataRegistry.get_config("combat_rules")
	var result := {
		"outcome": "hit", "damage": 0, "physical": 0, "elemental": 0, "element": "",
		"element_multiplier": 1.0, "is_crit": false, "blocked": false, "hit_chance": 0.0,
	}
	if rules.is_empty():
		result["outcome"] = "miss"
		return result

	var generator := rng if rng != null else _get_shared_rng()
	var a_stats: Dictionary = attacker.get("stats", {})
	var d_stats: Dictionary = defender.get("stats", {})
	var weapon: Dictionary = attacker.get("weapon", {})

	# 1. Hit or miss: accuracy against evasion.
	var hit_rules: Dictionary = rules["hit_chance"]
	var hit_chance := clampf(float(a_stats.get("accuracy", 0.0)) - float(d_stats.get("evasion", 0.0)),
			float(hit_rules["min"]), float(hit_rules["max"]))
	result["hit_chance"] = hit_chance
	if _roll(rolls, "hit", generator) >= hit_chance:
		result["outcome"] = "miss"
		return result

	# 2. Parry: the target turns the whole attack aside.
	if _roll(rolls, "parry", generator) < float(d_stats.get("parry_rate", 0.0)):
		result["outcome"] = "parry"
		return result

	# 3. Crit and block.
	var is_crit := _roll(rolls, "crit", generator) < float(a_stats.get("crit_chance", 0.0))
	var blocked := _roll(rolls, "block", generator) < float(d_stats.get("block_rate", 0.0))

	# 4. Base damage: weapon damage plus the attacker's power, times the skill.
	var power_stat := str(weapon.get("stat", "atk_power"))
	var unarmed: Dictionary = rules["unarmed"]
	var low := int(weapon.get("min", unarmed["min"]))
	var high := maxi(low, int(weapon.get("max", unarmed["max"])))
	var weapon_roll := mini(high, low + int(floor(_roll_fraction(rolls, "weapon", generator) * float(high - low + 1))))
	var skill := float(attacker.get("skill_multiplier", 1.0))
	var base := (float(weapon_roll) + float(a_stats.get(power_stat, 0.0))) * skill

	# 5. Defense (physical or magic) takes a share off.
	var defense_stat := str(rules["magic_defense_stat"]) if power_stat == "magic_power" else str(rules["physical_defense_stat"])
	var defense := maxf(0.0, float(d_stats.get(defense_stat, 0.0)))
	var reduction := minf(defense / (defense + float(rules["defense_constant"])), float(rules["max_reduction"]))
	var physical := base * (1.0 - reduction)

	# 6. Element damage from the weapon, scaled by the target's weaknesses.
	var element_name := str(weapon.get("element", ""))
	var element_mult := ElementalSystem.multiplier(element_name, defender.get("profile", {}))
	var elemental := float(weapon.get("element_amount", 0.0)) * skill * element_mult

	# 7. Crit, block and "takes more damage" effects apply to everything.
	var factor := float(defender.get("damage_taken_multiplier", 1.0))
	if is_crit:
		factor *= maxf(float(a_stats.get("crit_damage", 150.0)), 100.0) / 100.0
	if blocked:
		factor *= 1.0 - clampf(float(d_stats.get("block_mitigation", 0.0)), 0.0, 100.0) / 100.0

	result["physical"] = int(floor(physical * factor))
	result["elemental"] = int(floor(elemental * factor))
	result["damage"] = maxi(int(floor((physical + elemental) * factor)), int(rules["min_damage"]))
	result["element"] = element_name
	result["element_multiplier"] = element_mult
	result["is_crit"] = is_crit
	result["blocked"] = blocked
	return result


static func _roll(rolls: Dictionary, key: String, generator: RandomNumberGenerator) -> float:
	if rolls.has(key):
		return float(rolls[key])
	return generator.randf() * 100.0


static func _roll_fraction(rolls: Dictionary, key: String, generator: RandomNumberGenerator) -> float:
	if rolls.has(key):
		return clampf(float(rolls[key]), 0.0, 0.999999)
	return generator.randf()


static func _get_shared_rng() -> RandomNumberGenerator:
	if _shared_rng == null:
		_shared_rng = RandomNumberGenerator.new()
		_shared_rng.randomize()
	return _shared_rng
