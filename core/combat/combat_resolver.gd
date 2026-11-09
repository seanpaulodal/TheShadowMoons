class_name CombatResolver
extends RefCounted
## Runs one attack between two combatants: the math (DamageCalculator), the
## result on the target's health, and any status effect the weapon applies.
## It knows nothing about scenes or the screen.

static var _rng: RandomNumberGenerator


## Returns the damage result (see DamageCalculator) with "ok": true, plus
## "applied_status" when the weapon put an effect on the target, and "killed".
## Or {"ok": false, "error": CODE} if the attack could not happen.
## `rolls` replaces random numbers for tests ("status" in 0..100 as well).
static func attack(attacker: Combatant, defender: Combatant, skill_multiplier: float = 1.0,
		rolls: Dictionary = {}) -> Dictionary:
	if attacker.is_dead:
		return {"ok": false, "error": "ATTACKER_DEAD"}
	if defender.is_dead:
		return {"ok": false, "error": "TARGET_DEAD"}
	if not attacker.status.can_attack():
		return {"ok": false, "error": "CANNOT_ATTACK"}

	var result := DamageCalculator.resolve(attacker.combat_info(skill_multiplier),
			defender.combat_info(), rolls, _get_rng())
	result["ok"] = true
	result["attacker"] = attacker.display_name
	result["target"] = defender.display_name

	if result["outcome"] == "hit":
		defender.take_damage(int(result["damage"]), result)
		result["killed"] = defender.is_dead
		_apply_on_hit_status(attacker, defender, result, rolls)
	else:
		result["killed"] = false
		defender.report_no_damage(result)
	return result


static func _apply_on_hit_status(attacker: Combatant, defender: Combatant, result: Dictionary,
		rolls: Dictionary) -> void:
	if defender.is_dead:
		return
	var on_hit: Dictionary = attacker.attack_profile.get("on_hit", {})
	if on_hit.is_empty():
		return
	var roll := float(rolls["status"]) if rolls.has("status") else _get_rng().randf() * 100.0
	if roll >= float(on_hit.get("chance", 0.0)) * 100.0:
		return
	var applied := defender.status.apply(str(on_hit.get("effect", "")), {"from": attacker.display_name})
	if applied["ok"]:
		result["applied_status"] = applied["effect_id"]


static func _get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng
