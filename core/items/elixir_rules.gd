class_name ElixirRules
extends RefCounted
## Elixirs: a 7, 15 or 30 day potion that slowly restores a percent of maximum
## health, mana and stamina every few seconds, also while you are away. Pure
## logic on the character's "elixir" record {"id", "activated_at", "expires_at"}
## (times are Unix seconds). The definitions are in TSM_Consumable_Rules.json.


static func _rules() -> Dictionary:
	return DataRegistry.get_config("consumable_rules").get("elixirs", {})


static func types() -> Dictionary:
	return _rules().get("types", {})


static func tick_seconds() -> float:
	return maxf(1.0, float(_rules().get("tick_seconds", 10.0)))


static func is_elixir(item_id: String) -> bool:
	return types().has(item_id)


static func is_active(state: Dictionary, now: int) -> bool:
	return not state.is_empty() and now < int(state.get("expires_at", 0))


static func seconds_left(state: Dictionary, now: int) -> int:
	return maxi(0, int(state.get("expires_at", 0)) - now) if not state.is_empty() else 0


## "6d 4h", "5h 12m", "3m" - for the HUD.
static func time_text(seconds: int) -> String:
	var days := floori(float(seconds) / 86400.0)
	var hours := floori(float(seconds % 86400) / 3600.0)
	var minutes := floori(float(seconds % 3600) / 60.0)
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % maxi(1, minutes)


## Activates an elixir item. `current` is the elixir now active (or {}).
## Returns {"ok": true, "elixir": new record, "replaced": bool} or a failure.
static func activate(current: Dictionary, item_id: String, now: int) -> Dictionary:
	var definition: Dictionary = types().get(item_id, {})
	if definition.is_empty():
		return {"ok": false, "error": "NOT_AN_ELIXIR", "message": "That is not an elixir."}

	var replacing := is_active(current, now)
	if replacing and str(_rules().get("replace_rule", "higher_or_equal")) == "higher_or_equal":
		var old_rank := int(types().get(str(current.get("id", "")), {}).get("rank", 0))
		if int(definition.get("rank", 1)) < old_rank:
			return {"ok": false, "error": "WEAKER_ELIXIR", "message": "A stronger elixir is already active."}

	return {
		"ok": true,
		"replaced": replacing,
		"elixir": {
			"id": item_id,
			"activated_at": now,
			"expires_at": now + int(definition["days"]) * 86400,
		},
	}


## What one tick restores: {"hp": int, "mp": int, "sp": int} (at least 1 if the bar exists).
static func tick_amounts(state: Dictionary, max_hp: int, max_mp: int, max_sp: int) -> Dictionary:
	var definition: Dictionary = types().get(str(state.get("id", "")), {})
	return {
		"hp": _share(max_hp, float(definition.get("hp_percent", 0.0))),
		"mp": _share(max_mp, float(definition.get("mp_percent", 0.0))),
		"sp": _share(max_sp, float(definition.get("sp_percent", 0.0))),
	}


## How many ticks fit between two moments, counting only the time the elixir was
## active. `offline_cap` shortens very long absences (see offline_cap_hours).
static func ticks_between(state: Dictionary, from_unix: int, to_unix: int, offline_cap: bool = false) -> int:
	if state.is_empty():
		return 0
	var start := maxi(from_unix, int(state.get("activated_at", 0)))
	var finish := mini(to_unix, int(state.get("expires_at", 0)))
	if finish <= start:
		return 0
	var window := float(finish - start)
	if offline_cap:
		window = minf(window, float(_rules().get("offline_cap_hours", 24)) * 3600.0)
	return int(floor(window / tick_seconds()))


static func _share(maximum: int, percent: float) -> int:
	if maximum <= 0 or percent <= 0.0:
		return 0
	return maxi(1, int(floor(float(maximum) * percent / 100.0)))
