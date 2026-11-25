class_name WaypointRules
extends RefCounted
## The rules of waypoints, as pure checks: when one can be activated, when you
## can teleport. Each answers "" (allowed) or an error code, so the screen only
## has to show the message.

const MESSAGES := {
	"TOO_FAR": "Get closer to the waypoint.",
	"ENEMIES_NEAR": "Defeat the enemies near the waypoint first.",
	"ALREADY_ACTIVE": "This waypoint is already active.",
	"LOCKED": "That waypoint has not been activated yet.",
	"IN_COMBAT": "You can't teleport right after fighting.",
	"DEAD": "You can't teleport while dead.",
	"UNKNOWN": "Unknown waypoint.",
}


static func message(code: String) -> String:
	return str(MESSAGES.get(code, "That did not work."))


static func is_unlocked(character: Dictionary, waypoint_id: String) -> bool:
	return (character.get("waypoints", []) as Array).has(waypoint_id)


static func unlocked_count(character: Dictionary, map_id: String) -> int:
	var total := 0
	for entry in MapData.waypoints(map_id):
		if is_unlocked(character, str(entry["id"])):
			total += 1
	return total


## Activating: stand close, and no living enemy near the waypoint.
static func activation_error(already_active: bool, player_distance: float, enemies_near: int,
		radius: float) -> String:
	if already_active:
		return "ALREADY_ACTIVE"
	if player_distance > radius:
		return "TOO_FAR"
	if enemies_near > 0:
		return "ENEMIES_NEAR"
	return ""


## Teleporting: the waypoint must be active, you must be alive, and not just out of a fight.
static func teleport_error(character: Dictionary, waypoint_id: String, player_dead: bool,
		seconds_since_combat: float, combat_delay: float) -> String:
	if player_dead:
		return "DEAD"
	if MapData.waypoint(str(character.get("current_map", "map_1")), waypoint_id).is_empty():
		return "UNKNOWN"
	if not is_unlocked(character, waypoint_id):
		return "LOCKED"
	if seconds_since_combat < combat_delay:
		return "IN_COMBAT"
	return ""


## "35 m" / "1.2 km".
static func distance_text(meters: float) -> String:
	if meters >= 1000.0:
		var km = floor(meters / 100.0) / 10.0
		return "%.1f km" % km
	return "%d m" % roundi(meters)
