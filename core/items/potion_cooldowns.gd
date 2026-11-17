class_name PotionCooldowns
extends RefCounted
## One cooldown timer per potion: drinking a Minor Health Potion does not stop
## you drinking a Greater one, but you cannot drink the same one again until its
## timer is done. Seconds come from TSM_Consumable_Rules.json.

var _remaining: Dictionary = {}     # item_id -> seconds left
var _total: Dictionary = {}         # item_id -> the full cooldown, for the progress display


## How long this item's cooldown is: a hand-set override, else by what it
## restores (health / mana / stamina), else the default.
static func duration_for(item_id: String) -> float:
	var rules: Dictionary = DataRegistry.get_config("consumable_rules").get("cooldowns", {})
	var overrides: Dictionary = rules.get("overrides", {})
	if overrides.has(item_id):
		return float(overrides[item_id])
	var resource := str(ItemDB.consumable_effect(item_id).get("resource", ""))
	var by_resource: Dictionary = rules.get("by_resource", {})
	if by_resource.has(resource):
		return float(by_resource[resource])
	return float(rules.get("default_seconds", 5.0))


func start(item_id: String, seconds: float = -1.0) -> void:
	var length := seconds if seconds >= 0.0 else duration_for(item_id)
	_remaining[item_id] = length
	_total[item_id] = length


func is_ready(item_id: String) -> bool:
	return float(_remaining.get(item_id, 0.0)) <= 0.0


func remaining(item_id: String) -> float:
	return maxf(0.0, float(_remaining.get(item_id, 0.0)))


## 1.0 right after drinking, down to 0.0 when ready (for the cooldown shade on a button).
func fraction(item_id: String) -> float:
	var total := float(_total.get(item_id, 0.0))
	return clampf(remaining(item_id) / total, 0.0, 1.0) if total > 0.0 else 0.0


func update(delta: float) -> void:
	for item_id in _remaining.keys():
		_remaining[item_id] = maxf(0.0, float(_remaining[item_id]) - delta)
		if float(_remaining[item_id]) <= 0.0:
			_remaining.erase(item_id)
			_total.erase(item_id)
