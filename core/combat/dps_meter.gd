class_name DpsMeter
extends RefCounted
## Counts the damage something takes, for the training dummy's damage per second.
## Times are in seconds. By default it uses the game clock; tests pass `now`.

var total: int = 0
var hits: int = 0
var crits: int = 0
var misses: int = 0
var _events: Array = []    # [time, damage]


## Adds one attack result (see DamageCalculator). Damage over time counts too.
func record(result: Dictionary, now: float = -1.0) -> void:
	var time := now if now >= 0.0 else Time.get_ticks_msec() / 1000.0
	var outcome := str(result.get("outcome", ""))
	if outcome == "miss" or outcome == "parry":
		misses += 1
		return
	var damage := int(result.get("damage", 0))
	total += damage
	hits += 1
	if result.get("is_crit", false):
		crits += 1
	_events.append([time, damage])


## Damage per second over the last `window` seconds.
func dps(window: float = 5.0, now: float = -1.0) -> float:
	var time := now if now >= 0.0 else Time.get_ticks_msec() / 1000.0
	var sum := 0
	for event in _events:
		if time - float(event[0]) <= window:
			sum += int(event[1])
	return float(sum) / window


func reset() -> void:
	total = 0
	hits = 0
	crits = 0
	misses = 0
	_events.clear()
