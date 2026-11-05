class_name Progression
extends RefCounted
## Level and EXP rules, stat point spending, and rebirth checks.
## Pure logic: every function takes a character "state" dictionary and returns
## a new one, so nothing changes until the caller decides to keep the result.
##
## state = {"level": int, "exp": int, "stat_points": int, "rebirth": int}
## allocated = {"str": int, "int": int, ...}   (points the player has spent)


static func _config() -> Dictionary:
	return DataRegistry.get_config("progression")


static func max_level() -> int:
	return int(_config().get("max_level", 300))


static func max_rebirth() -> int:
	return int(_config().get("max_rebirth", 10))


## EXP needed to go from `level` to the next one. 0 at the maximum level.
static func exp_to_next(level: int, rebirth: int = 0) -> int:
	if level >= max_level():
		return 0
	var cfg := _config()
	var base := float(cfg.get("exp_base", 100))
	var exponent := float(cfg.get("exp_exponent", 2.0))
	var rebirth_factor := 1.0 + float(cfg.get("rebirth_exp_increase", 0.0)) * rebirth
	return maxi(1, int(floor(base * pow(float(maxi(level, 1)), exponent) * rebirth_factor)))


## Adds EXP and levels up as many times as the EXP allows.
## Returns {"state": new state, "levels_gained": int}.
static func add_exp(state: Dictionary, amount: int) -> Dictionary:
	var result := state.duplicate()
	var level := int(result.get("level", 1))
	var exp_now := int(result.get("exp", 0))
	var points := int(result.get("stat_points", 0))
	var rebirth := int(result.get("rebirth", 0))
	var per_level := int(_config().get("stat_points_per_level", 5))
	var gained := 0

	if amount > 0:
		exp_now += amount
	while level < max_level():
		var need := exp_to_next(level, rebirth)
		if exp_now < need:
			break
		exp_now -= need
		level += 1
		points += per_level
		gained += 1
	if level >= max_level():
		exp_now = 0    # nothing more to earn at the cap

	result["level"] = level
	result["exp"] = exp_now
	result["stat_points"] = points
	return {"state": result, "levels_gained": gained}


## Spends stat points on one attribute.
## Returns {"ok": true, "state": ..., "allocated": ...} or {"ok": false, "error": CODE, "message": text}.
static func allocate(state: Dictionary, allocated: Dictionary, attribute: String,
		amount: int = 1) -> Dictionary:
	if not StatCalculator.ATTRIBUTES.has(attribute):
		return _fail("UNKNOWN_ATTRIBUTE", "Unknown attribute: %s" % attribute)
	if amount < 1:
		return _fail("INVALID_AMOUNT", "Amount must be at least 1.")

	var points := int(state.get("stat_points", 0))
	if points < amount:
		return _fail("NOT_ENOUGH_POINTS", "Not enough stat points.")

	var cap := int(_config().get("max_attribute_points", 999))
	var current := int(allocated.get(attribute, 0))
	if current + amount > cap:
		return _fail("ATTRIBUTE_CAP", "That attribute is at its maximum.")

	var new_state := state.duplicate()
	new_state["stat_points"] = points - amount
	var new_allocated := allocated.duplicate()
	new_allocated[attribute] = current + amount
	return {"ok": true, "state": new_state, "allocated": new_allocated}


static func can_rebirth(state: Dictionary) -> bool:
	return int(state.get("level", 1)) >= max_level() \
			and int(state.get("rebirth", 0)) < max_rebirth()


## Resets level and EXP and adds one rebirth. Stat points and spent attributes
## are left untouched: what a rebirth rewards is still to be designed.
static func apply_rebirth(state: Dictionary) -> Dictionary:
	if not can_rebirth(state):
		return _fail("CANNOT_REBIRTH", "Reach the maximum level first (and under rebirth %d)." % max_rebirth())
	var new_state := state.duplicate()
	new_state["level"] = 1
	new_state["exp"] = 0
	new_state["rebirth"] = int(state.get("rebirth", 0)) + 1
	return {"ok": true, "state": new_state}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
