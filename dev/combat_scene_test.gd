extends Node
## DEV ONLY. Checks fighting in the real world scene (M5): the player attacking
## the training dummy, targeting, cooldown, weapons, status effects, damage
## numbers, the HUD and the attack button. Needs no login: it makes up a test
## character and saves nothing. Run with F6 and read the Output panel.

const SURE := {"hit": 0.0, "parry": 99.9, "crit": 99.9, "block": 99.9, "weapon": 0.5, "status": 0.0}

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _dummy: TrainingDummy
var _far_dummy: TrainingDummy
var _attacks: Array = []
var _messages: Array = []
var _targets: Array = []


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	Session.character = {
		"name": "Fighter", "class_id": "warrior", "level": 1, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()

	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	for node in get_tree().get_nodes_in_group("targetable"):
		if node.global_position.distance_to(Vector3(0, 0, -6)) < 0.5:
			_dummy = node
		else:
			_far_dummy = node
	_player.attacked.connect(func(result: Dictionary) -> void: _attacks.append(result))
	_player.attack_failed.connect(func(reason: String) -> void: _messages.append(reason))
	_player.target_changed.connect(func(target: Node3D) -> void: _targets.append(target))

	await _test_world_setup()
	await _test_attacking()
	await _test_weapons()
	await _test_status_effects()
	await _test_targeting()
	await _test_touch_button_and_hud()
	_test_floating_text()

	Session.save_enabled = true
	Session.clear()
	print("[fight] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[fight] PASS  ", label)
	else:
		_failed += 1
		print("[fight] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _stand_at(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	await _frames(3)


func _swing(overrides: Dictionary = {}) -> Dictionary:
	var rolls := SURE.duplicate()
	rolls.merge(overrides, true)
	var result := _player.try_attack(rolls)
	await _frames(1)
	return result


func _cooldown() -> void:
	await _frames(75)


func _equip(item_id: String) -> void:
	await Session.add_item(item_id, 1)
	var bag: Array = Session.character["inventory"]
	await Session.equip_item(str(bag[bag.size() - 1]["uid"]))
	await _frames(2)


# ---------- tests ----------

func _test_world_setup() -> void:
	print("[fight] --- the world ---")
	_report("a training dummy stands in front of the player", _dummy != null)
	_report("a second dummy stands further away", _far_dummy != null)
	_eq("the dummy has the data's health", _dummy.combatant.max_health(), 999999)
	_eq("the dummy has the data's level", _dummy.combatant.level, 999999)
	_eq("the dummy never dies", _dummy.combatant.immortal, true)
	_eq("the dummy gives no attack", _dummy.combatant.stats["atk_power"], 0.0)
	_eq("the player is a fighter on the player team", _player.combatant.team, "player")
	_eq("the player's health comes from the stats", _player.combatant.max_health(), 134)
	_eq("the HUD exists", _world.combat_hud != null, true)
	_near("warrior attack range is 3", _player.attack_range(), 3.0)


func _test_attacking() -> void:
	print("[fight] --- attacking ---")
	var out_of_range := _player.try_attack(SURE)
	_eq("too far away: nothing to attack", out_of_range["error"], "NO_TARGET")
	_eq("...and the player is told", _messages.back(), "No target in range")

	await _stand_at(Vector3(0, 0.2, -3.2))
	var full := _dummy.combatant.hp
	var first := await _swing()
	_eq("in range: the attack happens", first["ok"], true)
	_eq("bare hands 2 + attack 21 = 23 damage", first["damage"], 23)
	_eq("the dummy lost exactly that", full - _dummy.combatant.hp, 23)
	_eq("the dummy is now the target", _player.target, _dummy)
	_eq("the attack was announced", _attacks.size(), 1)
	_report("a damage number floats up", FloatingText.active_count() >= 1)
	_eq("the dummy's meter counted a hit", [_dummy.dps_meter.hits, _dummy.dps_meter.total], [1, 23])

	var too_soon := _player.try_attack(SURE)
	_eq("swinging again at once is refused (cooldown)", too_soon["error"], "COOLDOWN")
	await _cooldown()
	var second := await _swing()
	_eq("after the cooldown it works again", second["ok"], true)
	_eq("the dummy has lost 46 in total", full - _dummy.combatant.hp, 46)

	await _cooldown()
	var missed := await _swing({"hit": 99.0})
	_eq("a miss: outcome", missed["outcome"], "miss")
	_eq("a miss: no damage", full - _dummy.combatant.hp, 46)
	_eq("a miss is counted by the meter", _dummy.dps_meter.misses, 1)

	await _cooldown()
	var crit := await _swing({"crit": 0.0})
	_eq("crit: 23 x 1.5 = 34", crit["damage"], 34)
	_eq("crit is flagged", crit["is_crit"], true)
	_report("the meter has a DPS number", _dummy.dps_meter.dps() > 0.0)

	_dummy.combatant.take_damage(5000000)
	_eq("the dummy refills instead of dying", [_dummy.combatant.is_dead, _dummy.combatant.hp], [false, 999999])


func _test_weapons() -> void:
	print("[fight] --- weapons ---")
	await _cooldown()
	await _equip("wooden_sword")
	var sword := await _swing()
	_eq("wooden sword: weapon 14 + attack 36 = 50", sword["damage"], 50)

	await _cooldown()
	await _equip("flame_blade")
	var before := _dummy.combatant.hp
	var flame := await _swing()
	_eq("flame blade: (58 + attack 86) + 25 fire = 169", flame["damage"], 169)
	_eq("...of which 25 is fire", flame["elemental"], 25)
	_eq("...the weapon sets the target on fire", flame.get("applied_status", ""), "burn")
	_eq("the dummy is burning", _dummy.combatant.status.has("burn"), true)
	await _frames(70)
	_report("burning takes health on its own", before - flame["damage"] - _dummy.combatant.hp >= 9999,
			"health went from %d to %d" % [before - flame["damage"], _dummy.combatant.hp])

	await _cooldown()
	await _equip("archmage_staff")
	var staff := await _swing()
	_eq("a staff uses magic power", _player.combatant.attack_profile["stat"], "magic_power")
	_eq("...and its holy damage is separate", staff["elemental"], 50)
	_report("the staff attack worked", staff["ok"])


func _test_status_effects() -> void:
	print("[fight] --- status effects on the player ---")
	await _cooldown()
	_player.combatant.status.apply("Stun")
	var stunned := _player.try_attack(SURE)
	_eq("a stunned player cannot attack", stunned["error"], "CANNOT_ATTACK")
	var start := _player.global_position
	_player.move_override = Vector2(0, 1)
	await _frames(20)
	_report("a stunned player cannot move", _player.global_position.distance_to(start) < 0.05,
			"moved %s" % str(_player.global_position.distance_to(start)))
	_player.move_override = Vector2.ZERO
	_player.combatant.status.clear()

	var normal_speed := _player.move_speed()
	_player.combatant.status.apply("Slow")
	_near("slow cuts walking speed by 35%", _player.move_speed(), snappedf(normal_speed * 0.65, 0.01), 0.02)
	_player.combatant.status.clear()
	_near("the speed comes back when it ends", _player.move_speed(), normal_speed)

	_player.combatant.status.apply("Haste")
	_near("haste adds 30% speed", _player.move_speed(), snappedf(normal_speed * 1.3, 0.01), 0.02)
	_player.combatant.status.clear()

	var hp_before := _player.combatant.hp
	_player.combatant.take_damage(40)
	_player.combatant.status.apply("Regeneration")
	await _frames(125)
	_report("regeneration heals the player", _player.combatant.hp > hp_before - 40, "hp %d" % _player.combatant.hp)
	_player.combatant.status.clear()
	_player.combatant.heal(1000)


func _test_targeting() -> void:
	print("[fight] --- targeting ---")
	await _cooldown()
	await _stand_at(Vector3(0, 0.2, 0))
	var none := _player.try_attack(SURE)
	_eq("walking away: nothing in range any more", none["error"], "NO_TARGET")
	_eq("...the target is dropped", _player.target, null)

	_targets.clear()
	await _stand_at(Vector3(-6, 0.2, -7.5))
	await _cooldown()
	var near_far := await _swing()
	_eq("next to the other dummy: it becomes the target", _player.target, _far_dummy)
	_eq("the first dummy was not hit", _dummy.dps_meter.hits < _far_dummy.dps_meter.hits + 20, true)
	_eq("the target change was announced", _targets.size() >= 1 and _targets.back() == _far_dummy, true)
	_report("the attack landed on the far dummy", near_far["ok"] and _far_dummy.dps_meter.hits == 1)

	Session.character["class_id"] = "archer"
	_player.refresh_stats()
	_near("an archer reaches much further (range 10)", _player.attack_range(), 10.0)
	Session.character["class_id"] = "warrior"
	_player.refresh_stats()


func _test_touch_button_and_hud() -> void:
	print("[fight] --- attack button and HUD ---")
	var controls := TouchControls.new()
	add_child(controls)
	await get_tree().process_frame
	var size := get_viewport().get_visible_rect().size
	var button := controls.attack_center()
	_report("the attack button is at the bottom right", button.x > size.x * 0.6 and button.y > size.y * 0.5, str(button))

	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = button
	controls._input(touch)
	_eq("pressing the attack button holds attack", controls.attack_held, true)
	_eq("...and it does not move the joystick or camera", [controls.move_vector, controls.consume_look_delta()], [Vector2.ZERO, Vector2.ZERO])
	touch.pressed = false
	controls._input(touch)
	_eq("letting go stops attacking", controls.attack_held, false)

	var elsewhere := InputEventScreenTouch.new()
	elsewhere.index = 4
	elsewhere.pressed = true
	elsewhere.position = Vector2(size.x * 0.7, size.y * 0.3)
	controls._input(elsewhere)
	_eq("pressing elsewhere on the right does not attack", controls.attack_held, false)
	elsewhere.pressed = false
	controls._input(elsewhere)
	controls.queue_free()

	# The HUD shows the target.
	await _stand_at(Vector3(0, 0.2, -3.2))
	await _cooldown()
	await _swing()
	await _frames(10)
	var hud: CombatHud = _world.combat_hud
	_eq("the target frame is visible", hud._target_panel.visible, true)
	_report("it names the dummy", "Training Dummy" in hud._target_name.text, hud._target_name.text)
	_report("it shows the DPS meter", "Hits" in hud._target_dps.text, hud._target_dps.text)
	_report("the player's HP text is filled in", "/" in hud._hp_text.text, hud._hp_text.text)


func _test_floating_text() -> void:
	print("[fight] --- damage numbers ---")
	_eq("a plain hit shows the number", FloatingText.describe({"outcome": "hit", "damage": 35})["text"], "35")
	_eq("a crit says so", FloatingText.describe({"outcome": "hit", "damage": 52, "is_crit": true})["text"], "CRIT 52!")
	_eq("a miss says MISS", FloatingText.describe({"outcome": "miss"})["text"], "MISS")
	_eq("a parry says PARRY", FloatingText.describe({"outcome": "parry"})["text"], "PARRY")
	_eq("a block says so", FloatingText.describe({"outcome": "hit", "damage": 17, "blocked": true})["text"], "(block) 17")
	_eq("damage over time shows the number", FloatingText.describe({"outcome": "dot", "damage": 9, "element": "fire"})["text"], "9")
	_eq("fire damage over time is orange", FloatingText.describe({"outcome": "dot", "damage": 9, "element": "fire"})["color"], FloatingText.ELEMENT_COLORS["fire"])
	_report("a crit is bigger than a plain hit",
			FloatingText.describe({"outcome": "hit", "damage": 5, "is_crit": true})["scale"] > FloatingText.describe({"outcome": "hit", "damage": 5})["scale"])
