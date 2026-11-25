class_name MapData
extends RefCounted
## Reads a map from TSM_Maps.json and checks that it makes sense: waypoints and
## fountains inside the map and not on top of shops or camps, unique ids, and
## level ranges in order. Read only.


static func get_map(map_id: String) -> Dictionary:
	return DataRegistry.get_config("maps").get(map_id, {})


static func waypoints(map_id: String) -> Array:
	return get_map(map_id).get("waypoints", [])


static func waypoint(map_id: String, waypoint_id: String) -> Dictionary:
	for entry in waypoints(map_id):
		if str(entry["id"]) == waypoint_id:
			return entry
	return {}


static func fountains(map_id: String) -> Array:
	return get_map(map_id).get("fountains", [])


static func position_of(entry: Dictionary) -> Vector2:
	var at: Array = entry.get("position", [0, 0])
	return Vector2(float(at[0]), float(at[1]))


## Waypoints a new character already has (the starting town).
static func default_unlocked(map_id: String) -> Array:
	var ids: Array = []
	for entry in waypoints(map_id):
		if entry.get("unlocked_by_default", false):
			ids.append(str(entry["id"]))
	return ids


## Problems in the map layout (an empty list means all fine).
static func validate(map_id: String) -> Array:
	var problems: Array = []
	var map := get_map(map_id)
	if map.is_empty():
		return ["map %s does not exist" % map_id]
	var half := float(map.get("size", 200.0)) / 2.0
	var seen := {}

	var avoid: Array = []     # [name, position, radius]
	for shop in DataRegistry.get_config("shop_rules").get("shops", []):
		avoid.append(["shop %s" % str(shop["id"]), position_of(shop), 4.0])
	for camp in DataRegistry.get_config("world_camps").get(map_id, {}).get("camps", []):
		avoid.append(["camp %s" % str(camp["enemy_id"]), position_of(camp), float(camp.get("radius", 8)) + 2.0])

	for kind in ["waypoints", "fountains"]:
		for entry in map.get(kind, []):
			var id := str(entry.get("id", ""))
			var at := position_of(entry)
			if id == "" or seen.has(id):
				problems.append("%s: missing or duplicate id '%s'" % [kind, id])
			seen[id] = true
			if absf(at.x) > half - 2.0 or absf(at.y) > half - 2.0:
				problems.append("%s is outside the map" % id)
			for other in avoid:
				if at.distance_to(other[1]) < float(other[2]) + 2.5:
					problems.append("%s is on top of %s" % [id, str(other[0])])
			if at.distance_to(position_of({"position": map.get("spawn", [0, 0])})) < 2.5:
				problems.append("%s is on the spawn point" % id)

	for entry in map.get("waypoints", []):
		var range_: Array = entry.get("level_range", [1, 1])
		if int(range_[0]) > int(range_[1]):
			problems.append("%s: level range is backwards" % str(entry["id"]))
	if MapData.default_unlocked(map_id).is_empty():
		problems.append("no waypoint is unlocked at the start")
	return problems
