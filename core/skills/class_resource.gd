class_name ClassResource
extends RefCounted
## The class bar. It is the MP bar, renamed and recoloured for each class (Rage,
## Focus, Ammo...), and skills spend it. Rules per class (when it starts, how it
## refills, what builds it up, what drains it) are in TSM_Class_Resources.json.

const IDLE_SECONDS := 5.0        # "not fighting" for the idle refill


static func rules(class_id: String) -> Dictionary:
	return DataRegistry.get_config("class_resources").get("classes", {}).get(class_id.to_lower(), {})


static func label(class_id: String) -> String:
	return SkillDB.resource_label(str(rules(class_id).get("resource", "mana")))


static func short_label(class_id: String) -> String:
	return str(rules(class_id).get("short", "MP"))


static func color(class_id: String) -> Color:
	return Color(str(rules(class_id).get("color", "2f7fd1")))


## What the bar holds when a character first enters the game.
static func start_value(class_id: String, pool: int) -> int:
	return 0 if str(rules(class_id).get("start", "full")) == "empty" else pool


## Units per second the bar moves while nothing else happens (negative = draining).
## `seconds_idle` is the time since the last fight action.
static func rate(class_id: String, seconds_idle: float) -> float:
	var data := rules(class_id)
	var refill := float(data.get("regen_per_second", 0.0))
	if seconds_idle >= IDLE_SECONDS:
		refill += float(data.get("idle_regen_per_second", 0.0))
	var drain := 0.0
	if float(data.get("decay_per_second", 0.0)) > 0.0 and seconds_idle >= float(data.get("decay_delay", 0.0)):
		drain = float(data["decay_per_second"])
	return refill - drain


## What the bar gains from an event: "hit" (you hit an enemy), "hit_taken", "kill".
static func gain(class_id: String, event: String) -> float:
	var key: String = str({"hit": "gain_on_hit", "hit_taken": "gain_when_hit", "kill": "gain_on_kill"}.get(event, ""))
	return float(rules(class_id).get(key, 0.0)) if key != "" else 0.0
