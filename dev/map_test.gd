extends Node
## DEV ONLY. Checks the world (M9): the map data, the day and night sky and the
## three moons, the scenery, waypoints and teleporting, healing fountains and the
## minimap. Needs no login and saves nothing. Run with F6 and read the Output panel.

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _hud: CombatHud


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character()

	_test_map_data()
	_test_day_night_rules()
	_test_waypoint_rules()
	_test_session_waypoints()
	await _build_world()
	await _test_scenery()
	_world.clear_decor()
	await _frames(3)
	await _test_waypoints_and_activation()
	await _test_map_window_and_teleport()
	await _test_fountains()
	await _test_sky_and_moons()
	await _test_minimap()

	Session.save_enabled = true
	Session.clear()
	print("[map] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[map] PASS  ", label)
	else:
		_failed += 1
		print("[map] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_character() -> void:
	Session.character = {
		"name": "Fighter", "class_id": "warrior", "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _build_world() -> void:
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	_hud = _world.combat_hud
	_hud.fade_seconds = 0.03
	for camp in _world.camps:
		camp.queue_free()
	for node in get_tree().get_nodes_in_group("targetable"):
		if node is Enemy:
			node.queue_free()
	await _frames(3)


func _stand_at(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	await _frames(12)


func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


# ---------- map data ----------

func _test_map_data() -> void:
	print("[map] --- map data ---")
	_eq("map 1 has no layout problems", MapData.validate("map_1"), [])
	for problem in MapData.validate("map_1"):
		print("[map] PROBLEM ", problem)
	_eq("six waypoints", MapData.waypoints("map_1").size(), 6)
	_eq("two fountains", MapData.fountains("map_1").size(), 2)
	_eq("only the starting town is open at the start", MapData.default_unlocked("map_1"), ["oakhaven_village"])
	_eq("a waypoint is found by id", MapData.waypoint("map_1", "ruined_temple")["name"], "Ruined Temple")
	_eq("an unknown waypoint is not found", MapData.waypoint("map_1", "nowhere"), {})
	_eq("positions are read as x and z", MapData.position_of(MapData.waypoint("map_1", "goblin_hollow")), Vector2(16, -2))
	_eq("an unknown map is reported", MapData.validate("map_9").size(), 1)

	# The check really notices a bad layout.
	var entry: Dictionary = MapData.waypoint("map_1", "goblin_hollow")
	var original: Array = entry["position"]
	entry["position"] = [24, -16]                       # right in the middle of the goblin camp
	_report("a waypoint inside a camp is caught", MapData.validate("map_1").any(func(p: String) -> bool: return "goblin_hollow" in p and "camp" in p))
	entry["position"] = [0, 0]
	_report("a waypoint on the spawn point is caught", MapData.validate("map_1").any(func(p: String) -> bool: return "spawn" in p))
	entry["position"] = [500, 0]
	_report("a waypoint outside the map is caught", MapData.validate("map_1").any(func(p: String) -> bool: return "outside" in p))
	entry["position"] = original
	entry["level_range"] = [9, 3]
	_report("a backwards level range is caught", MapData.validate("map_1").any(func(p: String) -> bool: return "backwards" in p))
	entry["level_range"] = [1, 6]
	_eq("...and put right again", MapData.validate("map_1"), [])


# ---------- day and night ----------

func _test_day_night_rules() -> void:
	print("[map] --- day and night ---")
	var noon = DayNightRules.state_for_hour(12.0)
	var midnight = DayNightRules.state_for_hour(0.0)
	_near("noon: full sun", noon["sun_energy"], 1.15)
	_near("noon: not night", noon["night"], 0.0)
	_near("noon: the sun is high (75 degrees)", noon["sun_elevation"], 75.0, 0.1)
	_near("midnight: no sun", midnight["sun_energy"], 0.0)
	_near("midnight: full night", midnight["night"], 1.0)
	_report("midnight: the sun is below the horizon", midnight["sun_elevation"] < 0.0)
	_near("sunrise at 6: the sun is on the horizon", DayNightRules.state_for_hour(6.0)["sun_elevation"], 0.0, 0.1)
	_near("sunset at 18: the sun is on the horizon", DayNightRules.state_for_hour(18.0)["sun_elevation"], 0.0, 0.1)
	_report("the sky is brighter at noon than at midnight", _luminance(noon["sky_color"]) > _luminance(midnight["sky_color"]) * 3.0)
	_near("dawn is in between (6:30: sun 0.55)", DayNightRules.state_for_hour(6.5)["sun_energy"], 0.55)
	_near("dusk is in between (18:00: sun 0.6)", DayNightRules.state_for_hour(18.0)["sun_energy"], 0.6)

	var rising = true
	var previous = -1.0
	for step in range(50, 121):                        # 5:00 to 12:00
		var energy = float(DayNightRules.state_for_hour(float(step) / 10.0)["sun_energy"])
		if energy < previous - 0.0001:
			rising = false
		previous = energy
	_eq("from 5:00 to noon the sun only gets stronger", rising, true)
	var jump = absf(float(DayNightRules.state_for_hour(11.99)["sun_energy"]) - float(DayNightRules.state_for_hour(12.01)["sun_energy"]))
	_report("there are no sudden jumps in the light", jump < 0.01, str(jump))
	_near("hours wrap around: 25:00 is 1:00", DayNightRules.state_for_hour(25.0)["night"], DayNightRules.state_for_hour(1.0)["night"])

	_eq("hour text", DayNightRules.format_hour(14.6), "2:36 PM")
	_eq("midnight text", DayNightRules.format_hour(0.0), "12:00 AM")
	_eq("the last minute of the day", DayNightRules.format_hour(23.999), "11:59 PM")
	_eq("period: 3:00 is night", DayNightRules.period_name(3.0), "Night")
	_eq("period: 6:00 is dawn", DayNightRules.period_name(6.0), "Dawn")
	_eq("period: 12:00 is day", DayNightRules.period_name(12.0), "Day")
	_eq("period: 18:00 is dusk", DayNightRules.period_name(18.0), "Dusk")
	_eq("period: 21:00 is night", DayNightRules.period_name(21.0), "Night")
	_eq("a fixed hour comes from the data", DayNightRules.hour_from_rules({"mode": "fixed", "fixed_hour": 9.5}), 9.5)
	var real = DayNightRules.hour_from_rules({"mode": "real_clock", "time_scale": 1.0})
	_report("the real clock gives an hour between 0 and 24", real >= 0.0 and real < 24.0, str(real))


# ---------- waypoint rules ----------

func _test_waypoint_rules() -> void:
	print("[map] --- waypoint rules ---")
	_eq("activating: all fine", WaypointRules.activation_error(false, 2.0, 0, 3.2), "")
	_eq("activating: too far", WaypointRules.activation_error(false, 9.0, 0, 3.2), "TOO_FAR")
	_eq("activating: enemies near", WaypointRules.activation_error(false, 2.0, 2, 3.2), "ENEMIES_NEAR")
	_eq("activating: already active", WaypointRules.activation_error(true, 2.0, 0, 3.2), "ALREADY_ACTIVE")
	var character = {"current_map": "map_1", "waypoints": ["oakhaven_village", "goblin_hollow"]}
	_eq("teleporting: all fine", WaypointRules.teleport_error(character, "goblin_hollow", false, 10.0, 5.0), "")
	_eq("teleporting: a waypoint you have not activated", WaypointRules.teleport_error(character, "ruined_temple", false, 10.0, 5.0), "LOCKED")
	_eq("teleporting: right after a fight", WaypointRules.teleport_error(character, "goblin_hollow", false, 2.0, 5.0), "IN_COMBAT")
	_eq("teleporting: when dead", WaypointRules.teleport_error(character, "goblin_hollow", true, 10.0, 5.0), "DEAD")
	_eq("teleporting: an unknown place", WaypointRules.teleport_error(character, "nowhere", false, 10.0, 5.0), "UNKNOWN")
	_eq("two of six are active", WaypointRules.unlocked_count(character, "map_1"), 2)
	_eq("a distance in metres", WaypointRules.distance_text(34.6), "35 m")
	_eq("a long distance in kilometres", WaypointRules.distance_text(1250.0), "1.2 km")
	var every_code_has_text = true
	for code in ["TOO_FAR", "ENEMIES_NEAR", "ALREADY_ACTIVE", "LOCKED", "IN_COMBAT", "DEAD", "UNKNOWN"]:
		if WaypointRules.message(code) == "That did not work.":
			every_code_has_text = false
	_eq("every refusal has a message", every_code_has_text, true)


func _test_session_waypoints() -> void:
	print("[map] --- saved waypoints ---")
	_new_character()
	_eq("a new character starts with the home waypoint", Session.character["waypoints"], ["oakhaven_village"])
	var result = Session.unlock_waypoint("goblin_hollow")
	_eq("activating another works", [result["ok"], result["already"]], [true, false])
	_eq("...it is on the character", Session.character["waypoints"], ["oakhaven_village", "goblin_hollow"])
	_eq("...and waiting to be saved", Session.has_unsaved_changes(), true)
	_eq("activating it again changes nothing", Session.unlock_waypoint("goblin_hollow")["already"], true)
	_eq("...no duplicate", Session.character["waypoints"].size(), 2)
	_eq("an unknown waypoint is refused", Session.unlock_waypoint("nowhere")["error"], "UNKNOWN")
	Session.character.erase("waypoints")
	Session._fill_missing_fields()
	_eq("an old character without waypoints gets the home one", Session.character["waypoints"], ["oakhaven_village"])
	_new_character()


# ---------- scenery ----------

func _test_scenery() -> void:
	print("[map] --- scenery ---")
	var decor: MapDecor = _world.decor
	_report("a good number of trees (80 or more)", decor.tree_positions.size() >= 80, str(decor.tree_positions.size()))
	_report("rocks too (30 or more)", decor.rock_positions.size() >= 30, str(decor.rock_positions.size()))
	_eq("20 mountains in the distance", decor.mountain_count, 20)
	_report("the whole scenery is only a few nodes (cheap on a phone)", decor.get_child_count() < 40, str(decor.get_child_count()))

	var multi_meshes = 0
	for child in decor.get_children():
		if child is MultiMeshInstance3D:
			multi_meshes += 1
	_eq("trees (3 parts), rocks and mountains are 5 grouped draws", multi_meshes, 5)
	var body = decor.get_node("DecorBody") as StaticBody3D
	_eq("every solid thing shares one physics body", body.get_child_count(), decor.tree_positions.size() + decor.rock_positions.size() + 9)

	var keep_clear_ok = true
	var reserved: Array = [[Vector2.ZERO, 10.0]]
	for shop in DataRegistry.get_config("shop_rules")["shops"]:
		reserved.append([MapData.position_of(shop), 5.0])
	for camp in DataRegistry.get_config("world_camps")["map_1"]["camps"]:
		reserved.append([MapData.position_of(camp), float(camp["radius"]) + 4.0])
	for entry in MapData.waypoints("map_1"):
		reserved.append([MapData.position_of(entry), 4.5])
	for entry in MapData.fountains("map_1"):
		reserved.append([MapData.position_of(entry), 6.0])
	for spot in decor.tree_positions + decor.rock_positions:
		for zone in reserved:
			if (spot as Vector2).distance_to(zone[0]) < float(zone[1]):
				keep_clear_ok = false
	_eq("nothing grows at the start, in the market, the camps, or at waypoints and fountains", keep_clear_ok, true)

	var spaced = true
	for i in decor.tree_positions.size():
		for j in range(i + 1, decor.tree_positions.size()):
			if (decor.tree_positions[i] as Vector2).distance_to(decor.tree_positions[j]) < 5.0:
				spaced = false
	_eq("trees never touch each other", spaced, true)
	var inside = true
	for spot in decor.tree_positions:
		if absf(spot.x) > 94.0 or absf(spot.y) > 94.0:
			inside = false
	_eq("all trees are inside the walls", inside, true)

	var again = MapDecor.new()
	add_child(again)
	again.build("map_1", reserved)
	_eq("the same map always gets the same trees", again.tree_positions, decor.tree_positions)
	again.queue_free()


# ---------- waypoints ----------

func _test_waypoints_and_activation() -> void:
	print("[map] --- waypoints ---")
	_new_character()
	_player.refresh_stats()
	Session.character_changed.emit()
	await _frames(3)
	_eq("six waypoint obelisks stand in the world", _world.waypoints.size(), 6)
	var by_id = {}
	for waypoint in _world.waypoints:
		by_id[waypoint.waypoint_id] = waypoint
	_eq("the home waypoint is blue", (by_id["oakhaven_village"] as Waypoint).is_blue(), true)
	_eq("the others are red", (by_id["goblin_hollow"] as Waypoint).is_blue(), false)
	_eq("a red one says it is inactive", "(inactive)" in (by_id["goblin_hollow"] as Waypoint)._label.text, true)
	_eq("a blue one shows only its name", (by_id["oakhaven_village"] as Waypoint)._label.text, "Oakhaven Village")
	_eq("blue and red are different colours", (by_id["oakhaven_village"] as Waypoint)._crystal_material.albedo_color != (by_id["goblin_hollow"] as Waypoint)._crystal_material.albedo_color, true)
	_near("waypoints stand where the data says", (by_id["ruined_temple"] as Waypoint).global_position.x, 38.0)

	await _stand_at(Vector3(16, 0.2, 0.5))
	_eq("next to a red waypoint the button offers to activate it", _hud._interact_button.text, "Activate: Goblin Hollow")

	var guard = Enemy.new()
	guard.setup("green_goblin", Vector3(16, 0, 8), _world)
	guard.test_rolls = {"hit": 99.0, "parry": 99.9, "crit": 99.9, "block": 99.9, "weapon": 0.5}
	_world.add_child(guard)
	await _frames(3)
	_hud._interact_button.pressed.emit()
	_eq("with an enemy nearby it will not activate", (by_id["goblin_hollow"] as Waypoint).is_blue(), false)
	_report("...and says why", "enem" in _hud._message.text.to_lower(), _hud._message.text)
	guard.combatant.take_damage(100000)
	await _frames(3)
	_hud._interact_button.pressed.emit()
	await _frames(3)
	_eq("once the enemy is dead it activates", (by_id["goblin_hollow"] as Waypoint).is_blue(), true)
	_eq("it is saved on the character", Session.character["waypoints"].has("goblin_hollow"), true)
	_report("a banner announces it", "WAYPOINT" in _hud._banner.text, _hud._banner.text)
	_eq("its label no longer says inactive", "(inactive)" in (by_id["goblin_hollow"] as Waypoint)._label.text, false)
	await _frames(12)
	_eq("the button now says it is an active waypoint", _hud._interact_button.text, "Waypoint: Goblin Hollow")

	await _stand_at(Vector3(16, 0.2, 9.5))
	_eq("too far away there is no button", _hud._interact_button.visible, false)
	await _stand_at(Vector3(-22, 0.2, -9.5))
	_eq("a different waypoint, a different button", _hud._interact_button.text, "Activate: Spider Marsh")
	_eq("a waypoint with no enemies left near it can be activated from its button too",
			_hud.activate_waypoint(by_id["spider_marsh"])["ok"], true)
	_eq("pressing the key works the same way: nothing more to activate", _hud.activate_waypoint(by_id["spider_marsh"])["error"], "ALREADY_ACTIVE")


# ---------- map window and teleport ----------

func _test_map_window_and_teleport() -> void:
	print("[map] --- map window and teleporting ---")
	await _stand_at(Vector3(0, 0.2, 0))
	_player._combat_clock = 99.0
	_hud.open_map()
	await _frames(2)
	var window = _hud.map_window
	_eq("the Map window opens", window.visible, true)
	_eq("it counts the active waypoints (home, hollow, marsh)", "3 / 6" in window._summary.text, true)
	_report("...and names the map", "Oakhaven Wilds" in window._summary.text)
	_eq("it lists all six", window._list.get_child_count(), 6)
	var enabled = 0
	for row in window._list.get_children():
		var button = row.get_child(0).get_child(row.get_child(0).get_child_count() - 1) as Button
		if not button.disabled:
			enabled += 1
	_eq("only the three active ones can be teleported to", enabled, 3)
	_report("each row shows a level range", ((window._list.get_child(1).get_child(0).get_child(2)) as Label).text == "Lv 1 - 6")
	_report("...and the distance from you", ((window._list.get_child(0).get_child(0).get_child(3)) as Label).text.ends_with(" m"))

	var arrivals: Array = []
	_hud.teleported.connect(func(waypoint_id: String) -> void: arrivals.append(waypoint_id))
	var go = _hud.teleport_to("spider_marsh")
	_eq("teleporting to an active waypoint is accepted", go["ok"], true)
	await _frames(4)
	_eq("the screen is fading", _hud._fade.visible, true)
	_report("...with the place named", "Spider Marsh" in _hud._fade_label.text, _hud._fade_label.text)
	_eq("the controls are off while it happens", _world.controls.enabled, false)
	_eq("a second teleport is refused meanwhile", _hud.teleport_to("goblin_hollow").get("error", ""), "BUSY")
	await _frames(40)
	_eq("it finishes", arrivals, ["spider_marsh"])
	_eq("the fade is gone", _hud._fade.visible, false)
	_eq("the controls are back", _world.controls.enabled, true)
	var marsh = MapData.position_of(MapData.waypoint("map_1", "spider_marsh"))
	_report("the player is now at the Spider Marsh obelisk", Vector2(_player.global_position.x, _player.global_position.z).distance_to(marsh) < 5.0, str(_player.global_position))
	_eq("the windows were closed", window.visible, false)

	_player._combat_clock = 0.0
	_eq("right after a fight you can't teleport", _hud.teleport_to("goblin_hollow")["error"], "IN_COMBAT")
	_player._combat_clock = 99.0
	_eq("a waypoint you have not activated is refused", _hud.teleport_to("ashen_border")["error"], "LOCKED")
	_eq("an unknown one is refused", _hud.teleport_to("nowhere")["error"], "UNKNOWN")
	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(2)
	_eq("a dead player can't teleport", _hud.teleport_to("goblin_hollow")["error"], "DEAD")
	_player.revive()
	await _frames(3)

	# The window shows the refusal.
	_hud.open_map()
	_player._combat_clock = 0.0
	window._on_teleport("goblin_hollow")
	_report("the window shows why a teleport was refused", "fight" in window._message.text.to_lower() or "fighting" in window._message.text.to_lower(), window._message.text)
	_hud.close_windows()
	_player._combat_clock = 99.0


# ---------- fountains ----------

func _test_fountains() -> void:
	print("[map] --- healing fountains ---")
	_eq("two fountains", _world.fountains.size(), 2)
	var village: HealingFountain = _world.fountains[0]
	_near("the village fountain stands where the data says", village.global_position.z, 22.0)
	_near("it heals 10 per second", village.heal_per_second, 10.0)

	_player.revive()
	await _stand_at(Vector3(0, 0.2, 20.0))
	_player._combat_clock = 0.0
	_player.combatant.take_damage(100)
	var hp = _player.combatant.hp
	await _frames(60)
	_player._combat_clock = 0.0
	var gained = _player.combatant.hp - hp
	_report("a second at the fountain heals about 10", gained >= 9 and gained <= 11, "+%d" % gained)
	_eq("the fountain is glowing brighter while it heals", village._sparkles.speed_scale, 2.0)
	await _frames(40)
	_report("it shows a number floating up", FloatingText.active_count() >= 1)

	await _stand_at(Vector3(0, 0.2, 27.0))
	_player._combat_clock = 0.0
	hp = _player.combatant.hp
	await _frames(60)
	_eq("away from the fountain nothing is healed", _player.combatant.hp, hp)
	_eq("...and it stops glowing brighter", village._sparkles.speed_scale, 1.0)

	await _stand_at(Vector3(0, 0.2, 20.0))
	_player.combatant.heal(100000)
	hp = _player.combatant.hp
	await _frames(30)
	_eq("at full health there is nothing to heal", _player.combatant.hp, hp)

	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(40)
	_eq("the dead are not healed by it", _player.combatant.hp, 0)
	_player.revive()
	await _stand_at(Vector3(0, 0.2, 20.0))

	var rate: Dictionary = MapData.get_map("map_1")
	rate["heal_per_second"] = 20
	var quick = HealingFountain.new()
	quick.position = Vector3(60, 0, 60)
	_world.add_child(quick)
	await _frames(2)
	_near("the healing rate comes from the data (20 when changed)", quick.heal_per_second, 20.0)
	rate["heal_per_second"] = 10
	quick.queue_free()


# ---------- sky and moons ----------

func _test_sky_and_moons() -> void:
	print("[map] --- sky and moons ---")
	var sky: DayNight = _world.day_night
	_eq("the world has a sky", sky != null, true)
	_eq("three moons", sky.moon_count(), 3)
	var sun: DirectionalLight3D = _world._sun
	var environment: Environment = _world._environment

	sky.hour_override = 12.0
	sky.apply_now()
	_near("at noon the sun is strong", sun.light_energy, 1.15)
	_eq("...and the moons are hidden", [sky.moon_visible(0), sky.moon_visible(1), sky.moon_visible(2)], [false, false, false])
	var day_ambient = environment.ambient_light_energy
	var day_sky = environment.background_color

	sky.hour_override = 0.0
	sky.apply_now()
	_near("at midnight there is only faint moonlight", sun.light_energy, 0.28)
	_eq("...all three moons are out", [sky.moon_visible(0), sky.moon_visible(1), sky.moon_visible(2)], [true, true, true])
	_report("...the ambient light is dimmer", environment.ambient_light_energy < day_ambient)
	_report("...and the sky is darker", _luminance(environment.background_color) < _luminance(day_sky))
	_eq("fog is on", environment.fog_enabled, true)
	_report("fog is thicker at night", environment.fog_density > 0.005)

	sky.hour_override = 6.5
	sky.apply_now()
	_near("at dawn the sun is lower (0.55)", sun.light_energy, 0.55)
	_report("...and the moons are fading (still shown)", sky.moon_visible(0))
	sky.hour_override = 9.0
	sky.apply_now()
	_eq("in the morning the moons are gone", sky.moon_visible(0), false)

	# The moons keep their place in the sky.
	sky.hour_override = 0.0
	sky.apply_now()
	await _frames(3)
	var camera = get_viewport().get_camera_3d()
	var first: Vector3 = sky._moons[0]["direction"]
	var offset: Vector3 = (sky._moons[0]["mesh"] as MeshInstance3D).global_position - camera.global_position
	_report("a moon sits at its fixed direction from the camera", offset.normalized().distance_to(first) < 0.01 and absf(offset.length() - DayNight.MOON_DISTANCE) < 1.0)
	var azimuth = deg_to_rad(205.0)
	var elevation = deg_to_rad(42.0)
	var expected = Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	_report("...from the data's azimuth and elevation (moon 1)", first.distance_to(expected) < 0.001)
	await _stand_at(Vector3(30, 0.2, -30))
	await _frames(3)
	var after: Vector3 = (sky._moons[0]["mesh"] as MeshInstance3D).global_position - get_viewport().get_camera_3d().global_position
	_report("walking 40 metres does not make the moon move closer", after.normalized().distance_to(first) < 0.01 and absf(after.length() - DayNight.MOON_DISTANCE) < 1.0)

	# The HUD clock.
	sky.hour_override = 14.6
	await _frames(80)
	_eq("the HUD clock shows the time of day", _hud._time_label.text, "Day  2:36 PM")
	sky.hour_override = -1.0
	var real_hour = sky.current_hour()
	_report("with no override the real clock is used", real_hour >= 0.0 and real_hour < 24.0)
	sky.hour_override = 12.0
	sky.apply_now()


# ---------- minimap ----------

func _test_minimap() -> void:
	print("[map] --- minimap ---")
	await _stand_at(Vector3(0, 0.2, 0))
	var minimap = _hud.minimap
	_eq("a minimap is on the screen", minimap != null, true)
	_eq("it starts small and round", minimap.expanded, false)
	_near("its size is the compact size", minimap.size.x, Minimap.COMPACT_SIZE, 2.0)
	_eq("there are four menu buttons (Bag, Char, Skills, Map)", _hud.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text in ["Bag", "Char", "Skills", "Map"]).size(), 4)

	# Put a few things in the world to mark.
	var goblins: Array = []
	for i in 3:
		var enemy = Enemy.new()
		enemy.setup("green_goblin", Vector3(30 + i * 3, 0, 30), _world)
		_world.add_child(enemy)
		goblins.append(enemy)
	LootDrop.spawn(_world, Vector3(-20, 0, 20), "iron_ring")
	await _frames(15)
	var markers = minimap.collect_markers()
	var counts = {}
	for marker in markers:
		counts[marker["kind"]] = int(counts.get(marker["kind"], 0)) + 1
	_eq("it marks the 3 enemies", counts.get("enemy", 0), 3)
	_eq("...the dropped item", counts.get("loot", 0), 1)
	_eq("...the 5 shopkeepers", counts.get("npc", 0), 5)
	_eq("...the 3 active waypoints in blue", counts.get("waypoint_on", 0), 3)
	_eq("...the 3 inactive ones in red", counts.get("waypoint_off", 0), 3)
	_eq("...the 2 fountains", counts.get("fountain", 0), 2)
	_eq("enemy markers know the enemy's level", markers.filter(func(m: Dictionary) -> bool: return m["kind"] == "enemy")[0]["level"], 3)
	goblins[0].combatant.take_damage(100000)
	await _frames(15)
	var after_death = 0
	for marker in minimap.collect_markers():
		if marker["kind"] == "enemy":
			after_death += 1
	_eq("a dead enemy leaves the map", after_death, 2)

	_eq("map to screen: 10 metres east at 2 px per metre", Minimap.to_map(Vector2(10, 0), Vector2.ZERO, Vector2(100, 100), 2.0), Vector2(120, 100))
	_eq("map to screen: the centre goes to the origin", Minimap.to_map(Vector2(5, 5), Vector2(5, 5), Vector2(100, 100), 3.0), Vector2(100, 100))
	_eq("something 30 m away is on the small map", Minimap.in_circle(Vector2(30, 0), Minimap.COMPACT_RANGE - 1.5), true)
	_eq("something 50 m away is not", Minimap.in_circle(Vector2(50, 0), Minimap.COMPACT_RANGE - 1.5), false)
	_eq("a diagonal 40 m away (28 + 28) is out of range", Minimap.in_circle(Vector2(31, 31), Minimap.COMPACT_RANGE - 1.5), false)

	var tap = InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	minimap._gui_input(tap)
	_eq("tapping the minimap opens the big map", minimap.expanded, true)
	_eq("...it is a big rectangle", minimap.size, Minimap.EXPANDED_SIZE)
	_eq("...it counts as an open window", _hud.is_window_open(), true)
	_eq("...the controls are off", _world.controls.enabled, false)
	_eq("...with a seven-line legend", Minimap.LEGEND.size(), 7)
	var every_colour = true
	for entry in Minimap.LEGEND:
		if not Minimap.COLORS.has(entry[1]):
			every_colour = false
	_eq("...and each legend line has its colour", every_colour, true)
	await _frames(12)
	minimap.queue_redraw()
	await _frames(2)
	minimap._gui_input(tap)
	_eq("tapping again closes it", minimap.expanded, false)
	_near("...and it is small again", minimap.size.x, Minimap.COMPACT_SIZE, 2.0)
	_eq("...the controls are back", _world.controls.enabled, true)

	minimap.toggle()
	_hud.open_inventory()
	_eq("opening the Bag closes the big map", [minimap.expanded, _hud.inventory_window.visible], [false, true])
	_hud.close_windows()
	_eq("closing the windows leaves the controls on", _world.controls.enabled, true)
