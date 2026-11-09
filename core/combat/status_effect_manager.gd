class_name StatusEffectManager
extends RefCounted
## The status effects on ONE combatant (poison, slow, stun, ...). The effects
## themselves are defined in TSM_Status_Effects.json. This class only keeps
## track of which are active, ticks them, and reports what they do:
##   update()    -> damage / healing that happens this moment
##   modifiers() -> stat changes, in the format StatCalculator understands
##   flags       -> things the target cannot do (move / attack / cast)

signal changed
signal removed(effect_id: String)

const KINDS: Array[String] = ["dot", "hot", "buff", "debuff", "cc"]
const STACKING: Array[String] = ["refresh", "stack", "ignore"]

var _active: Dictionary = {}    # effect_id -> {"stacks", "remaining", "tick_timer", "source"}


## "Armor Break" -> "armor_break", "Weaken" -> "weakness". "" if unknown.
static func resolve_id(effect_name: String) -> String:
	var key := effect_name.strip_edges().to_lower().replace(" ", "_")
	if not DataRegistry.get_status_effect(key).is_empty():
		return key
	for effect_id in DataRegistry.get_ids("status_effects"):
		for alias in DataRegistry.get_status_effect(effect_id).get("aliases", []):
			if str(alias).strip_edges().to_lower().replace(" ", "_") == key:
				return str(effect_id)
	return ""


## Puts an effect on the target. Stacking rules come from the data:
## "refresh" restarts the timer, "stack" adds a stack (up to max_stacks) and
## restarts the timer, "ignore" does nothing while it is already active.
func apply(effect_name: String, source: Dictionary = {}) -> Dictionary:
	var effect_id := resolve_id(effect_name)
	if effect_id == "":
		return {"ok": false, "error": "UNKNOWN_EFFECT"}
	var effect_def := DataRegistry.get_status_effect(effect_id)
	var duration := float(effect_def["duration"])
	var max_stacks := maxi(1, int(effect_def.get("max_stacks", 1)))
	var stacking := str(effect_def.get("stacking", "refresh"))

	if _active.has(effect_id):
		var entry: Dictionary = _active[effect_id]
		if stacking == "ignore":
			return {"ok": true, "effect_id": effect_id, "stacks": entry["stacks"], "ignored": true}
		if stacking == "stack":
			entry["stacks"] = mini(int(entry["stacks"]) + 1, max_stacks)
		entry["remaining"] = duration
	else:
		_active[effect_id] = {"stacks": 1, "remaining": duration, "tick_timer": 0.0, "source": source}
	changed.emit()
	return {"ok": true, "effect_id": effect_id, "stacks": _active[effect_id]["stacks"]}


## Moves time forward. Returns what happened: a list of
## {"effect_id", "kind": "damage" | "heal", "amount": float, "element": String, "source": Dictionary}.
func update(delta: float, max_health: float) -> Array:
	var events: Array = []
	var expired: Array = []
	for effect_id in _active:
		var entry: Dictionary = _active[effect_id]
		var effect_def := DataRegistry.get_status_effect(effect_id)
		var step := minf(delta, float(entry["remaining"]))

		if effect_def.has("tick"):
			var tick_def: Dictionary = effect_def["tick"]
			var interval := maxf(0.05, float(tick_def.get("interval", 1.0)))
			entry["tick_timer"] = float(entry["tick_timer"]) + step
			while float(entry["tick_timer"]) >= interval - 0.0001:
				entry["tick_timer"] = float(entry["tick_timer"]) - interval
				var amount := (float(tick_def.get("percent_max_health", 0.0)) / 100.0 * max_health
						+ float(tick_def.get("flat", 0.0))) * int(entry["stacks"])
				events.append({
					"effect_id": effect_id,
					"kind": "heal" if tick_def.get("heal", false) else "damage",
					"amount": amount,
					"element": str(tick_def.get("element", "physical")),
					"source": entry["source"],
				})

		entry["remaining"] = float(entry["remaining"]) - step
		if float(entry["remaining"]) <= 0.0001:
			expired.append(effect_id)

	for effect_id in expired:
		_active.erase(effect_id)
		removed.emit(effect_id)
	if not expired.is_empty():
		changed.emit()
	return events


func has(effect_id: String) -> bool:
	return _active.has(effect_id)


func stacks(effect_id: String) -> int:
	return int(_active.get(effect_id, {}).get("stacks", 0))


func remaining(effect_id: String) -> float:
	return float(_active.get(effect_id, {}).get("remaining", 0.0))


func active_ids() -> Array:
	return _active.keys()


func remove(effect_id: String) -> void:
	if _active.erase(effect_id):
		removed.emit(effect_id)
		changed.emit()


## Removes every effect that may be cleansed (all of them, by default).
func cleanse() -> void:
	for effect_id in _active.keys():
		if DataRegistry.get_status_effect(effect_id).get("cleansable", true):
			_active.erase(effect_id)
			removed.emit(effect_id)
	changed.emit()


func clear() -> void:
	var had := not _active.is_empty()
	for effect_id in _active.keys():
		removed.emit(effect_id)
	_active.clear()
	if had:
		changed.emit()


## Stat changes from all active effects, scaled by their stacks.
func modifiers() -> Array:
	var result: Array = []
	for effect_id in _active:
		var count: int = _active[effect_id]["stacks"]
		for entry in DataRegistry.get_status_effect(effect_id).get("modifiers", []):
			result.append({
				"stat": str(entry["stat"]),
				"flat": float(entry.get("flat", 0.0)) * count,
				"percent": float(entry.get("percent", 0.0)) * count,
				"source": "status:%s" % effect_id,
			})
	return result


func has_flag(flag: String) -> bool:
	for effect_id in _active:
		if (DataRegistry.get_status_effect(effect_id).get("flags", []) as Array).has(flag):
			return true
	return false


func can_move() -> bool:
	return not has_flag("cannot_move")


func can_attack() -> bool:
	return not has_flag("cannot_attack")


func can_cast() -> bool:
	return not has_flag("cannot_cast")


## 1.0 normally; 1.15 while marked (+15% damage taken).
func damage_taken_multiplier() -> float:
	var extra := 0.0
	for effect_id in _active:
		extra += float(DataRegistry.get_status_effect(effect_id).get("damage_taken_percent", 0.0)) \
				* int(_active[effect_id]["stacks"])
	return maxf(0.0, 1.0 + extra / 100.0)


## Checks the effect data. Returns a list of problems (empty means all fine).
static func validate() -> Array:
	var problems: Array = []
	var stat_defs: Dictionary = DataRegistry.get_config("stat_rules").get("stats", {})
	for effect_id in DataRegistry.get_ids("status_effects"):
		var effect_def := DataRegistry.get_status_effect(effect_id)
		if not KINDS.has(str(effect_def.get("kind", ""))):
			problems.append("%s: unknown kind '%s'" % [effect_id, str(effect_def.get("kind"))])
		if float(effect_def.get("duration", 0.0)) <= 0.0:
			problems.append("%s: duration must be above 0" % effect_id)
		if not STACKING.has(str(effect_def.get("stacking", "refresh"))):
			problems.append("%s: unknown stacking '%s'" % [effect_id, str(effect_def.get("stacking"))])
		if effect_def.has("tick") and float(effect_def["tick"].get("interval", 1.0)) <= 0.0:
			problems.append("%s: tick interval must be above 0" % effect_id)
		for entry in effect_def.get("modifiers", []):
			if not stat_defs.has(str(entry.get("stat", ""))):
				problems.append("%s: modifier on unknown stat '%s'" % [effect_id, str(entry.get("stat"))])
	return problems
