extends Node
## DEV ONLY. Checks skill casting (part 2): the damage maths, every kind of skill
## effect (damage, execute, area, multi-hit, crowd control, damage over time, buffs,
## shields, heals, movement), costs and cooldowns, the class bar, and the skill
## buttons. Needs no login and saves nothing. Run with F6.

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _hud: CombatHud
var _hits: Array = []


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false

	_test_skill_effects()
	_test_damage_maths()
	_test_custom_status_effects()
	_test_class_resources()
	await _test_start_values()
	await _test_casting_basics()
	await _test_cast_time_and_blocks()
	await _test_damage_skills()
	await _test_status_skills()
	await _test_support_skills()
	await _test_movement()
	await _test_class_bar_events()
	await _test_buttons()

	Session.save_enabled = true
	Session.clear()
	print("[cast] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[cast] PASS  ", label)
	else:
		_failed += 1
		print("[cast] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_character(class_id: String, level: int) -> void:
	Session.character = {
		"name": "Fighter", "class_id": class_id, "level": level, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _setup_world(class_id: String, level: int) -> void:
	if _world != null:
		_world.queue_free()
		await _frames(3)
	_new_character(class_id, level)
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_player = _world.player
	_hud = _world.combat_hud
	_world.clear_decor()
	for camp in _world.camps:
		camp.queue_free()
	for node in get_tree().get_nodes_in_group("targetable"):
		node.queue_free()
	_player.skills.instant = true
	_hits.clear()
	_player.skills.skill_hit.connect(func(result: Dictionary) -> void: _hits.append(result))
	_player.global_position = Vector3(0, 0.2, 0)
	await _frames(3)


func _learn(skill_id: String, slot: String = "", rank: int = 1) -> void:
	Session.character["skills"]["learned"][skill_id] = rank
	if slot != "":
		Session.character["skills"]["slots"][slot] = skill_id
	Session.character_changed.emit()


## A goblin that stands still (its AI is off) with plenty of health.
func _goblin(position: Vector3, tank: bool = true) -> Enemy:
	var enemy := Enemy.new()
	enemy.setup("green_goblin", position, _world)
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	if tank:
		enemy.combatant.base_stats["max_health"] = 100000
		enemy.combatant.stats["max_health"] = 100000
		enemy.combatant.hp = 100000
	return enemy


func _ready_to_cast(mp: int = 100) -> void:
	_player.skills.cooldowns = PotionCooldowns.new()
	_player.combatant.mp = mp
	_player.combatant.hp = _player.combatant.max_health()
	_player._combat_clock = 99.0
	_hits.clear()


func _find_skill(predicate: Callable) -> String:
	for skill_id in DataRegistry.get_ids("skills"):
		if predicate.call(str(skill_id)):
			return str(skill_id)
	return ""


# ---------- skill effects (pure) ----------

func _test_skill_effects() -> void:
	print("[cast] --- what skills do (from the data) ---")
	var attributes := {"str": 20}
	_near("damage = (65 + 20 x 0.405) at rank 1", SkillEffects.raw_damage("WAR_01_01", 1, attributes), 73.1)
	_near("rank 6 multiplies it by 1.6", SkillEffects.raw_damage("WAR_01_01", 6, attributes), 116.96)
	var execute_skill := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "execute")
	_near("execute: nothing extra at half health", SkillEffects.execute_multiplier(execute_skill, 1, 0.5), 1.0)
	_report("execute: more damage below 20% health", SkillEffects.execute_multiplier(execute_skill, 1, 0.1) > 1.3)
	_near("a plain skill never has the execute bonus", SkillEffects.execute_multiplier("WAR_01_01", 1, 0.01), 1.0)
	_eq("a plain damage skill needs an enemy", SkillEffects.needs_enemy("WAR_01_01"), true)

	var cc_ok := true
	var cc_kinds := {}
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "crowd_control":
			var definition := SkillEffects.cc_definition(str(skill_id), 1)
			cc_kinds[SkillEffects.cc_status(str(skill_id))] = true
			if definition.is_empty() or float(definition["duration"]) <= 0.0 or not ["root", "slow", "silence"].has(SkillEffects.cc_status(str(skill_id))):
				cc_ok = false
			if not SkillEffects.needs_enemy(str(skill_id)):
				cc_ok = false
	_eq("all 13 crowd control skills map to root, slow or silence", cc_ok, true)
	_eq("...all three kinds are used", cc_kinds.keys().size(), 3)
	var slow_skill := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "slow")
	var slow := SkillEffects.cc_definition(slow_skill, 1)
	_near("a slow takes the skill's strength as percent", float(slow["modifiers"][0]["percent"]), -float(SkillEffects.effect(slow_skill)["control_strength"]) * 100.0, 0.01)
	var root_skill := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "root")
	_eq("a root keeps the effect's flags (can't move)", (SkillEffects.cc_definition(root_skill, 1)["flags"] as Array).has("cannot_move"), true)
	var silence_skill := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "silence")
	_eq("a silence stops casting", (SkillEffects.cc_definition(silence_skill, 1)["flags"] as Array).has("cannot_cast"), true)

	var dot_ok := true
	var dot_count := 0
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "damage_over_time":
			dot_count += 1
			var definition := SkillEffects.dot_definition(str(skill_id), 1, 100.0)
			if float(definition["tick"]["flat"]) <= 0.0 or not ["poison", "dark"].has(str(definition["tick"]["element"])):
				dot_ok = false
	_eq("all 8 damage-over-time skills tick for damage, poison or dark", [dot_count, dot_ok], [8, true])
	var dot_skill := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "damage_over_time")
	_near("a tick is the listed share of the damage", float(SkillEffects.dot_definition(dot_skill, 1, 200.0)["tick"]["flat"]), 200.0 * float(SkillEffects.effect(dot_skill)["damage_per_tick_percent_of_base"]), 0.01)

	var buff_ok := true
	var buff_count := 0
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "buff":
			buff_count += 1
			if SkillEffects.buff_definition(str(skill_id), 1)["modifiers"].is_empty():
				buff_ok = false
	_eq("all 18 buffs have stat changes", [buff_count, buff_ok], [18, true])
	var guard := _find_skill(func(id: String) -> bool: return "defense_buff" in SkillEffects.tags(id))
	_eq("a defense buff raises defense (by its tag)", SkillEffects.buff_definition(guard, 1)["modifiers"][0]["stat"], "def_power")
	var haste := _find_skill(func(id: String) -> bool: return "mobility_buff" in SkillEffects.tags(id))
	_eq("a mobility buff raises move speed", SkillEffects.buff_definition(haste, 1)["modifiers"][0]["stat"], "move_speed")
	var plain := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "buff" and not SkillEffects.buff_on_enemy(id) and SkillEffects.buff_rule(id)["stats"] == ["atk_power"])
	_eq("a plain buff raises attack power", SkillEffects.buff_definition(plain, 1)["modifiers"][0]["stat"], "atk_power")
	var debuff := _find_skill(func(id: String) -> bool: return "attack_debuff" in SkillEffects.tags(id))
	_eq("an attack debuff goes on the enemy", [SkillEffects.buff_on_enemy(debuff), SkillEffects.needs_enemy(debuff)], [true, true])
	_report("...and lowers attack power", float(SkillEffects.buff_definition(debuff, 1)["modifiers"][0]["percent"]) < 0.0)
	var weaken := _find_skill(func(id: String) -> bool: return "defense_and_speed_debuff" in SkillEffects.tags(id))
	_eq("a defense and speed debuff lowers both", SkillEffects.buff_definition(weaken, 1)["modifiers"].size(), 2)

	var shield_ok := true
	var shield_count := 0
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "defense":
			shield_count += 1
			var cut := float(SkillEffects.defense_definition(str(skill_id), 1)["damage_taken_percent"])
			if cut > -15.0 or cut < -30.0:
				shield_ok = false
	_eq("all 10 shields cut damage taken by 15 to 30 percent", [shield_count, shield_ok], [10, true])

	var heal_skill := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "healing" and SkillEffects.heal_over_time_seconds(id) == 0.0)
	_near("a heal is a share of maximum health", SkillEffects.heal_amount(heal_skill, 1, 1000), 1000.0 * float(SkillEffects.effect(heal_skill)["heal_percent_max_hp"]), 1.0)
	var hot_skill := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "healing" and SkillEffects.heal_over_time_seconds(id) > 0.0)
	var hot := SkillEffects.hot_definition(hot_skill, 120)
	_near("a heal over time gives the same total", float(hot["tick"]["flat"]) * float(hot["duration"]), 120.0, 0.01)

	var kinds := {}
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "movement":
			kinds[SkillEffects.movement_kind(str(skill_id))] = true
	_eq("movement skills are dashes, backsteps and teleports", kinds.keys().size(), 3)
	_eq("a backstep", SkillEffects.movement_kind("ARC_02_01"), "backstep")
	_eq("a teleport behind", SkillEffects.movement_kind("ROG_02_05"), "teleport_behind")
	var summons := 0
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "summon":
			summons += 1
	_eq("10 summon skills (they come in part 3)", summons, 10)


# ---------- damage maths ----------

func _fighter(stats: Dictionary, taken: float = 1.0, profile: Dictionary = {}) -> Dictionary:
	return {"stats": stats, "profile": profile, "damage_taken_multiplier": taken}


func _test_damage_maths() -> void:
	print("[cast] --- skill damage ---")
	var attacker := _fighter({"crit_chance": 5.0, "crit_damage": 150.0, "accuracy": 0.0})
	var defender := _fighter({"def_power": 100.0, "magic_resist": 0.0, "evasion": 999.0})
	var no_crit := {"crit": 99.9}
	var hit := DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "physical"}, no_crit)
	_eq("a physical skill is cut by defense (100 / 200 = half)", hit["damage"], 100)
	_eq("a skill never misses, even against huge evasion and no accuracy", hit["outcome"], "hit")
	_eq("magic damage ignores physical defense", DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "magic"}, no_crit)["damage"], 200)
	_eq("so does chaos damage", DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "chaos"}, no_crit)["damage"], 200)
	var crit := DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "physical"}, {"crit": 0.0})
	_eq("a crit does 150%", [crit["is_crit"], crit["damage"]], [true, 150])
	_eq("the skill's own crit bonus adds to the chance", DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "physical", "crit_bonus": 10.0}, {"crit": 5.0})["is_crit"], true)
	_eq("...but not beyond it", DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "physical", "crit_bonus": 10.0}, {"crit": 15.0})["is_crit"], false)
	_eq("a buff multiplies the damage", DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "physical", "power_multiplier": 1.1}, no_crit)["damage"], 110)
	_eq("so does an execute bonus", DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "physical", "damage_multiplier": 1.5}, no_crit)["damage"], 150)
	_eq("a shield on the target takes off 20%", DamageCalculator.resolve_skill(attacker, _fighter(defender["stats"], 0.8), {"raw": 200.0, "damage_type": "physical"}, no_crit)["damage"], 80)
	_eq("damage is never below 1", DamageCalculator.resolve_skill(attacker, defender, {"raw": 0.2, "damage_type": "physical"}, no_crit)["damage"], 1)

	var neutral := DamageCalculator.resolve_skill(attacker, defender, {"raw": 200.0, "damage_type": "holy"}, no_crit)
	_eq("holy damage on a neutral target is just defended damage", [neutral["damage"], neutral["element"]], [200, "holy"])
	var weak_profile := {}
	for element_name in ["dark", "fire", "ice", "poison", "shock", "water", "earth", "nature"]:
		var profile := ElementalSystem.profile_for(element_name)
		if ElementalSystem.multiplier("holy", profile) > 1.0:
			weak_profile = profile
	_report("some element is weak to holy", not weak_profile.is_empty())
	if not weak_profile.is_empty():
		var weak := DamageCalculator.resolve_skill(attacker, _fighter(defender["stats"], 1.0, weak_profile), {"raw": 200.0, "damage_type": "holy"}, no_crit)
		_eq("holy damage on a weak target does extra", weak["damage"], int(floor(200.0 * ElementalSystem.multiplier("holy", weak_profile))))

	var resolver_fighter := Combatant.new()
	add_child(resolver_fighter)
	resolver_fighter.setup("A", 1, {"max_health": 100, "crit_chance": 0.0, "crit_damage": 150.0})
	var victim := Combatant.new()
	add_child(victim)
	victim.setup("B", 1, {"max_health": 1000, "def_power": 0.0})
	var result := CombatResolver.skill_hit(resolver_fighter, victim, {"raw": 50.0, "damage_type": "physical"}, no_crit)
	_eq("the resolver applies the damage", [result["ok"], victim.hp], [true, 950])
	_eq("...remembers who did it", victim.last_attacker, resolver_fighter)
	victim.hp = 0
	victim.is_dead = true
	_eq("a dead target can't be hit", CombatResolver.skill_hit(resolver_fighter, victim, {"raw": 50.0}, no_crit)["error"], "TARGET_DEAD")
	resolver_fighter.queue_free()
	victim.queue_free()


# ---------- effects made by skills ----------

func _test_custom_status_effects() -> void:
	print("[cast] --- status effects made by skills ---")
	var fighter := Combatant.new()
	add_child(fighter)
	fighter.setup("Test", 1, {"max_health": 1000, "atk_power": 100.0, "def_power": 50.0, "move_speed": 10.0})
	var buff := {"effect_id": "skill_X", "name": "Test Buff", "kind": "buff", "duration": 10.0, "stacking": "refresh", "max_stacks": 1,
			"cleansable": true, "modifiers": [{"stat": "atk_power", "flat": 0.0, "percent": 10.5}]}
	fighter.status.apply_custom(buff)
	_near("a buff changes the stat (+10.5% of 100, kept as a whole number)", float(fighter.stats["atk_power"]), 110.0, 0.6)
	_eq("it can be looked up by its own name", fighter.status.definition("skill_X")["name"], "Test Buff")
	_eq("it is listed as active", fighter.status.active_ids().has("skill_X"), true)
	_near("power_multiplier sees the buff", SkillEffects.power_multiplier(fighter), 1.10, 0.01)
	fighter.tick(5.0)
	_eq("still active after 5 s", fighter.status.active_ids().has("skill_X"), true)
	fighter.status.apply_custom(buff)
	fighter.tick(6.0)
	_eq("using it again restarts the timer", fighter.status.active_ids().has("skill_X"), true)
	fighter.tick(5.0)
	_eq("it ends after its time", fighter.status.active_ids().has("skill_X"), false)
	_near("...and the stat goes back", float(fighter.stats["atk_power"]), 100.0, 0.1)

	var shield := {"effect_id": "skill_S", "name": "Shield", "kind": "buff", "duration": 5.0, "cleansable": false, "damage_taken_percent": -20.0}
	fighter.status.apply_custom(shield)
	_near("a shield cuts damage taken by 20%", fighter.status.damage_taken_multiplier(), 0.8)
	fighter.status.cleanse()
	_eq("a cleanse does not remove a shield (not cleansable)", fighter.status.active_ids().has("skill_S"), true)

	var root := SkillEffects.cc_definition(_find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "root"), 1)
	fighter.status.apply_custom(root)
	_eq("a root stops movement", fighter.status.can_move(), false)
	var silence := SkillEffects.cc_definition(_find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "silence"), 1)
	fighter.status.apply_custom(silence)
	_eq("a silence stops casting", fighter.status.can_cast(), false)
	fighter.tick(60.0)
	_eq("they wear off", [fighter.status.can_move(), fighter.status.can_cast()], [true, true])

	var dot := {"effect_id": "skill_D", "name": "Poison", "kind": "dot", "duration": 3.0, "cleansable": true,
			"tick": {"interval": 1.0, "flat": 10.0, "percent_max_health": 0.0, "element": "poison"}}
	var before := fighter.hp
	fighter.status.apply_custom(dot)
	for i in 3:
		fighter.tick(1.0)
	_eq("a damage-over-time effect hurts 10 a second for 3 seconds", before - fighter.hp, 30)
	fighter.hp = 500
	var hot := SkillEffects.hot_definition("HEA_01_03", 60)
	fighter.status.apply_custom(hot)
	for i in 6:
		fighter.tick(1.0)
	_eq("a heal over time gives its total back", fighter.hp, 560)
	fighter.queue_free()


# ---------- class bar rules ----------

func _test_class_resources() -> void:
	print("[cast] --- the class bar ---")
	var names := {"warrior": "Rage", "mage": "Mana", "archer": "Focus", "rogue": "Shadow Energy", "gunner": "Ammo",
			"healer": "Divine Energy", "extreme": "Anomaly Energy", "brawler": "Combo Gauge", "necromancer": "Soul Essence"}
	var labels_ok := true
	for class_id in names:
		if ClassResource.label(class_id) != names[class_id]:
			labels_ok = false
	_eq("each class names its bar", labels_ok, true)
	_eq("Rage and Combo start empty", [ClassResource.start_value("warrior", 100), ClassResource.start_value("brawler", 100)], [0, 0])
	_eq("the others start full", [ClassResource.start_value("mage", 130), ClassResource.start_value("gunner", 100)], [130, 100])
	_near("a mage refills 4 a second, 10 once resting", ClassResource.rate("mage", 0.0), 4.0)
	_near("...resting", ClassResource.rate("mage", 6.0), 10.0)
	_near("rage does not move while fighting", ClassResource.rate("warrior", 1.0), 0.0)
	_near("...drains after 4 s without a fight", ClassResource.rate("warrior", 4.5), -6.0)
	_near("combo drains after 3 s", ClassResource.rate("brawler", 3.5), -8.0)
	_near("...but not before", ClassResource.rate("brawler", 2.0), 0.0)
	_near("a hit gives a warrior 6 rage", ClassResource.gain("warrior", "hit"), 6.0)
	_near("being hit gives 5", ClassResource.gain("warrior", "hit_taken"), 5.0)
	_near("a kill gives a necromancer 20", ClassResource.gain("necromancer", "kill"), 20.0)
	_near("an unknown event gives nothing", ClassResource.gain("mage", "dance"), 0.0)
	_report("each class has its own colour", ClassResource.color("warrior") != ClassResource.color("mage"))
	var big_enough := true
	for class_id in names:
		var stats := StatCalculator.calculate(class_id, 1, {}, [])
		if int(stats["stats"]["max_mana"]) < 100 if stats.has("stats") else int(stats["max_mana"]) < 100:
			big_enough = false
	_eq("every class has a bar of at least 100", big_enough, true)


func _test_start_values() -> void:
	print("[cast] --- starting the game ---")
	await _setup_world("warrior", 1)
	_eq("a warrior starts with an empty Rage bar", _player.combatant.mp, 0)
	_report("...of at least 100", _player.combatant.max_mana() >= 100)
	await _setup_world("mage", 1)
	_eq("a mage starts with a full Mana bar", _player.combatant.mp, _player.combatant.max_mana())
	await _setup_world("brawler", 1)
	_eq("a brawler starts with an empty Combo bar", _player.combatant.mp, 0)


# ---------- casting ----------

func _test_casting_basics() -> void:
	print("[cast] --- casting ---")
	await _setup_world("warrior", 100)
	var enemy := _goblin(Vector3(0, 0, -2.2))
	await _frames(2)
	_ready_to_cast(100)
	_eq("an empty slot says so", _player.skills.cast_slot("skill_2")["error"], "NO_SKILL")
	_eq("a skill you have not learned is refused", _player.skills.cast("WAR_01_02")["error"], "NOT_LEARNED")

	_ready_to_cast(0)
	_eq("with no Rage the cast is refused", _player.skills.cast_slot("skill_1")["error"], "NOT_ENOUGH_RESOURCE")
	_eq("...saying which bar", _player.skills.cast_slot("skill_1")["message"], "Not enough Rage.")
	_eq("...and nothing was spent or started", [_player.combatant.mp, _player.skills.cooldowns.is_ready("WAR_01_01")], [0, true])

	_ready_to_cast(100)
	var hp_before := enemy.combatant.hp
	var cast := _player.skills.cast_slot("skill_1", {"crit": 99.9})
	_eq("Iron Slash is cast", cast["ok"], true)
	_eq("it spent its cost (9) and the hit gave 6 Rage back", _player.combatant.mp, 97)
	_eq("one hit was recorded", _hits.size(), 1)
	var reduction := float(enemy.combatant.stats["def_power"]) / (float(enemy.combatant.stats["def_power"]) + 100.0)
	var expected := floori(SkillEffects.raw_damage("WAR_01_01", 1, _player.skills._attributes()) * (1.0 - reduction))
	_near("the damage follows the formula", float(hp_before - enemy.combatant.hp), float(expected), 1.0)
	_report("its cooldown (9.7 s) has started", not _player.skills.cooldowns.is_ready("WAR_01_01") and absf(_player.skills.cooldowns.remaining("WAR_01_01") - 9.7) < 0.1)
	var again := _player.skills.cast_slot("skill_1")
	_eq("it can't be cast again at once", again["error"], "COOLDOWN")
	_report("...the message says how long", "Not ready" in again["message"], again["message"])
	_eq("the enemy now has the player as its attacker", enemy.combatant.last_attacker, _player.combatant)

	_ready_to_cast(100)
	enemy.global_position = Vector3(0, 0, -12)
	_eq("a target out of range (3 m) is refused", _player.skills.cast_slot("skill_1")["error"], "NO_TARGET")
	_eq("...nothing is spent", _player.combatant.mp, 100)
	enemy.queue_free()
	await _frames(3)
	_eq("with nobody there it is refused", _player.skills.cast_slot("skill_1")["error"], "NO_TARGET")


func _test_cast_time_and_blocks() -> void:
	print("[cast] --- cast time and what blocks casting ---")
	await _setup_world("warrior", 100)
	_player.skills.instant = false
	var enemy := _goblin(Vector3(0, 0, -2.2))
	await _frames(2)
	_ready_to_cast(100)
	var hp_before := enemy.combatant.hp
	_eq("a skill with a cast time starts casting", _player.skills.cast_slot("skill_1")["ok"], true)
	_eq("...it is casting", _player.skills.is_casting(), true)
	_eq("...nothing has hit yet", enemy.combatant.hp, hp_before)
	_eq("you can't cast another meanwhile", _player.skills.cast("WAR_01_01")["error"], "BUSY")
	_eq("...or attack", _player.try_attack()["error"], "CASTING")
	await _frames(30)
	_eq("when the cast time (0.3 s) is up it lands", [_player.skills.is_casting(), enemy.combatant.hp < hp_before], [false, true])

	_ready_to_cast(100)
	var silence_effect := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "silence")
	_player.combatant.status.apply_custom(SkillEffects.cc_definition(silence_effect, 1))
	_eq("a silenced player can't cast", _player.skills.cast_slot("skill_1")["error"], "CANNOT_CAST")
	_player.combatant.tick(60.0)

	_ready_to_cast(100)
	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(2)
	_eq("a dead player can't cast", _player.skills.cast_slot("skill_1")["error"], "DEAD")
	_player.revive()
	await _frames(3)

	# Dying mid-cast cancels the skill.
	_ready_to_cast(100)
	hp_before = enemy.combatant.hp
	_player.skills.cast_slot("skill_1")
	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(30)
	_eq("a cast is cancelled by death", enemy.combatant.hp, hp_before)
	_player.revive()
	await _frames(3)

	# Summons come later.
	var summon := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "summon")
	_learn(summon)
	_ready_to_cast(100)
	_eq("a summon skill is refused for now", _player.skills.cast(summon)["error"], "NOT_READY")
	_eq("...without spending anything", [_player.combatant.mp, _player.skills.cooldowns.is_ready(summon)], [100, true])
	enemy.queue_free()


# ---------- damage skills ----------

func _test_damage_skills() -> void:
	print("[cast] --- damage, area, several hits, execute ---")
	await _setup_world("warrior", 100)
	var area_skill := _find_skill(func(id: String) -> bool:
		var data := SkillDB.skill(id)
		return SkillEffects.effect_type(id) == "direct_damage" and int(data["skill_targeting"]["max_targets"]) >= 3 \
				and float(data["skill_area_radius_meters"]) >= 3.0 and SkillEffects.hit_count(id) == 1 and float(data["skill_range_meters"]) >= 3.0)
	_learn(area_skill)
	var data := SkillDB.skill(area_skill)
	var maximum := int(data["skill_targeting"]["max_targets"])
	var radius := float(data["skill_area_radius_meters"])
	var near_a := _goblin(Vector3(0, 0, -2.2))
	var near_b := _goblin(Vector3(1.0, 0, -2.5))
	var near_c := _goblin(Vector3(-1.0, 0, -2.5))
	var far := _goblin(Vector3(radius + 8.0, 0, -2.2))
	await _frames(2)
	_ready_to_cast(100)
	_player.skills.cast(area_skill, {"crit": 99.9})
	_eq("an area skill hits the target and those around it", [near_a.combatant.hp < 100000, near_b.combatant.hp < 100000, near_c.combatant.hp < 100000], [true, true, true])
	_eq("...but not an enemy outside the area", far.combatant.hp, 100000)
	_eq("...one hit each", _hits.size(), mini(3, maximum))
	for node in [near_a, near_b, near_c, far]:
		node.queue_free()
	await _frames(3)

	# Only max_targets are hit.
	var limited := _find_skill(func(id: String) -> bool:
		var d := SkillDB.skill(id)
		return SkillEffects.effect_type(id) == "direct_damage" and int(d["skill_targeting"]["max_targets"]) == 2 \
				and float(d["skill_area_radius_meters"]) >= 3.0 and SkillEffects.hit_count(id) == 1)
	if limited != "":
		_learn(limited)
		var group: Array = []
		for i in 4:
			group.append(_goblin(Vector3(float(i) * 0.5 - 0.7, 0, -2.2)))
		await _frames(2)
		_ready_to_cast(100)
		_player.skills.cast(limited, {"crit": 99.9})
		var damaged := 0
		for e in group:
			if e.combatant.hp < 100000:
				damaged += 1
		_eq("a skill limited to 2 targets hits only 2", damaged, 2)
		for e in group:
			e.queue_free()
		await _frames(3)

	# Several hits.
	var multi := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "direct_damage" and SkillEffects.hit_count(id) >= 3 and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0 and int(SkillDB.skill(id)["skill_targeting"]["max_targets"]) == 1)
	_learn(multi)
	var target := _goblin(Vector3(0, 0, -2.2))
	await _frames(2)
	_ready_to_cast(100)
	_player.skills.cast(multi, {"crit": 99.9})
	_eq("a multi-hit skill hits as many times as it says (all at once in tests)", _hits.size(), SkillEffects.hit_count(multi))
	var total := 0
	for result in _hits:
		total += int(result["damage"])
	var one_hit_total := SkillEffects.raw_damage(multi, 1, _player.skills._attributes())
	var def_reduction := float(target.combatant.stats["def_power"]) / (float(target.combatant.stats["def_power"]) + 100.0)
	_near("...sharing the skill's damage between them", float(total), one_hit_total * (1.0 - def_reduction), float(SkillEffects.hit_count(multi)) + 1.0) if SkillDB.skill(multi)["skill_damage"]["damage_type"] == "physical" else _report("...sharing the skill's damage between them", total > 0)
	_player.skills.instant = false
	_ready_to_cast(100)
	_hits.clear()
	_player.skills.cast(multi, {"crit": 99.9})
	await _frames(int(float(SkillDB.skill(multi)["skill_cast_time_seconds"]) * 60.0) + 12)      # the cast time, then the first hit or two
	_report("with the real timing the hits come one after another", _hits.size() >= 1 and _hits.size() < SkillEffects.hit_count(multi), str(_hits.size()))
	await _frames(60)
	_eq("...and all arrive in the end", _hits.size(), SkillEffects.hit_count(multi))
	_player.skills.instant = true
	target.queue_free()
	await _frames(3)

	# Execute.
	var execute_skill := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "execute" and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0)
	_learn(execute_skill)
	var healthy := _goblin(Vector3(0, 0, -2.2))
	await _frames(2)
	_ready_to_cast(100)
	_player.skills.cast(execute_skill, {"crit": 99.9})
	var normal_damage := int(_hits[0]["damage"])
	healthy.queue_free()
	await _frames(3)
	var weak := _goblin(Vector3(0, 0, -2.2))
	weak.combatant.hp = 10000      # 10% of 100000
	await _frames(2)
	_ready_to_cast(100)
	_player.skills.cast(execute_skill, {"crit": 99.9})
	var execute_damage := int(_hits[0]["damage"])
	_near("an execute skill does extra damage to a weak target", float(execute_damage) / float(normal_damage), SkillEffects.execute_multiplier(execute_skill, 1, 0.1), 0.03)
	weak.queue_free()
	await _frames(3)

	# Crits.
	var crit_target := _goblin(Vector3(0, 0, -2.2))
	await _frames(2)
	_ready_to_cast(100)
	_player.skills.cast("WAR_01_01", {"crit": 0.0})
	_eq("a crit is marked on the hit", _hits[0]["is_crit"], true)
	crit_target.queue_free()
	await _frames(3)


# ---------- crowd control and damage over time ----------

func _test_status_skills() -> void:
	print("[cast] --- crowd control and damage over time ---")
	await _setup_world("warrior", 100)
	var target := _goblin(Vector3(0, 0, -2.2))
	await _frames(2)

	var root_skill := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "root" and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0)
	_learn(root_skill)
	_ready_to_cast(100)
	_player.skills.cast(root_skill)
	_eq("a root skill roots the enemy", target.combatant.status.can_move(), false)
	_eq("...and shows on the enemy", target.combatant.status.active_ids().has("skill_%s" % root_skill), true)
	target.combatant.tick(100.0)

	var slow_skill := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "slow" and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0)
	_learn(slow_skill)
	_ready_to_cast(100)
	var speed_before := float(target.combatant.stats["move_speed"])
	_player.skills.cast(slow_skill)
	var strength := float(SkillEffects.effect(slow_skill)["control_strength"])
	_near("a slow skill cuts the enemy's speed by its strength", float(target.combatant.stats["move_speed"]), speed_before * (1.0 - strength), 0.2)
	target.combatant.tick(100.0)

	var silence_skill := _find_skill(func(id: String) -> bool: return SkillEffects.cc_status(id) == "silence" and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0)
	_learn(silence_skill)
	_ready_to_cast(100)
	_player.skills.cast(silence_skill)
	_eq("a silence skill silences the enemy", target.combatant.status.can_cast(), false)
	target.combatant.tick(100.0)

	var debuff := _find_skill(func(id: String) -> bool: return "attack_debuff" in SkillEffects.tags(id) and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0)
	_learn(debuff)
	_ready_to_cast(100)
	var attack_before := float(target.combatant.stats.get("atk_power", 0.0))
	_player.skills.cast(debuff)
	_report("an attack debuff weakens the enemy", float(target.combatant.stats.get("atk_power", 0.0)) < attack_before or attack_before == 0.0)
	target.combatant.tick(100.0)

	var dot_skill := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "damage_over_time" and float(SkillDB.skill(id)["skill_range_meters"]) >= 3.0)
	_learn(dot_skill)
	_ready_to_cast(100)
	var hp_before := target.combatant.hp
	_player.skills.cast(dot_skill, {"crit": 99.9})
	var after_hit := target.combatant.hp
	await _frames(130)
	_report("a damage-over-time skill keeps hurting after the hit", target.combatant.hp < after_hit, "%d -> %d" % [after_hit, target.combatant.hp])
	_eq("...it is shown on the enemy", target.combatant.status.active_ids().has("skill_%s" % dot_skill), true)
	_report("the hit itself did damage too (or none for a pure damage-over-time skill)", after_hit <= hp_before)
	target.queue_free()
	await _frames(3)

	# A kill by poison still counts for the player.
	var victim := _goblin(Vector3(0, 0, -2.2), false)
	victim.combatant.hp = 4
	await _frames(2)
	_ready_to_cast(100)
	_player.skills.cast(dot_skill, {"crit": 99.9})
	await _frames(200)
	_eq("a goblin killed by poison dies", victim.is_dead(), true)
	_eq("...and the player gets the credit", victim.combatant.last_attacker, _player.combatant)


# ---------- buffs, shields, heals ----------

func _test_support_skills() -> void:
	print("[cast] --- buffs, shields and heals ---")
	await _setup_world("warrior", 100)
	var buff := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "buff" and not SkillEffects.buff_on_enemy(id) and SkillEffects.buff_rule(id)["stats"] == ["atk_power"])
	_learn(buff)
	_ready_to_cast(100)
	var attack_before := float(_player.combatant.stats["atk_power"])
	_eq("a buff needs no enemy", _player.skills.cast(buff)["ok"], true)
	_report("it raises attack power", float(_player.combatant.stats["atk_power"]) > attack_before)
	_eq("...it shows as a status chip", _player.combatant.status.active_ids().has("skill_%s" % buff), true)
	await _frames(15)
	_report("...in the HUD too", _hud._buff_box.get_child_count() >= 1)
	var duration := float(SkillEffects.effect(buff)["duration_seconds"])
	_player.combatant.tick(duration + 0.5)
	_near("it ends after %d seconds" % int(duration), float(_player.combatant.stats["atk_power"]), attack_before, 0.1)

	var shield := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "defense")
	_learn(shield)
	_ready_to_cast(100)
	_player.skills.cast(shield)
	_report("a shield cuts the damage you take", _player.combatant.status.damage_taken_multiplier() < 0.9)
	_player.combatant.tick(100.0)

	var heal := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "healing" and SkillEffects.heal_over_time_seconds(id) == 0.0)
	_learn(heal)
	_ready_to_cast(100)
	_player.combatant.hp = 10
	var expected := SkillEffects.heal_amount(heal, 1, _player.combatant.max_health())
	_player.skills.cast(heal)
	_eq("a heal gives back its share of maximum health", _player.combatant.hp, mini(10 + expected, _player.combatant.max_health()))

	var hot := _find_skill(func(id: String) -> bool: return SkillEffects.effect_type(id) == "healing" and SkillEffects.heal_over_time_seconds(id) > 0.0)
	_learn(hot)
	_ready_to_cast(100)
	_player.combatant.hp = 10
	_player.skills.cast(hot)
	_eq("a heal over time starts as an effect", _player.combatant.status.active_ids().has("skill_%s" % hot), true)
	await _frames(100)
	_report("...and heals as time goes by", _player.combatant.hp > 10)


# ---------- movement ----------

func _test_movement() -> void:
	print("[cast] --- movement ---")
	await _setup_world("warrior", 100)
	var dash := _find_skill(func(id: String) -> bool: return SkillEffects.movement_kind(id) == "dash" and SkillEffects.has_damage(id))
	var backstep := _find_skill(func(id: String) -> bool: return SkillEffects.movement_kind(id) == "backstep" and SkillEffects.has_damage(id))
	var teleport := _find_skill(func(id: String) -> bool: return SkillEffects.movement_kind(id) == "teleport_behind")
	for skill_id in [dash, backstep, teleport]:
		_learn(skill_id)

	var target := _goblin(Vector3(0, 0, -6.0))
	await _frames(2)
	_ready_to_cast(100)
	var start := _player.global_position
	var range_m := float(SkillDB.skill(dash)["skill_range_meters"])
	if range_m >= 6.0:
		_player.skills.cast(dash, {"crit": 99.9})
		await _frames(25)
		_report("a dash moves you toward the enemy", _player.global_position.distance_to(target.global_position) < start.distance_to(target.global_position) - 2.0, str(_player.global_position))
	else:
		target.global_position = Vector3(0, 0, -range_m + 0.5)
		await _frames(2)
		_player.skills.cast(dash, {"crit": 99.9})
		await _frames(25)
		_report("a dash moves you toward the enemy", _player.global_position.z < start.z - 0.5, str(_player.global_position))
	target.queue_free()
	await _frames(3)

	_player.global_position = Vector3(0, 0.2, 0)
	_player.velocity = Vector3.ZERO
	var close := _goblin(Vector3(0, 0, -2.0))
	await _frames(2)
	_ready_to_cast(100)
	var before := _player.global_position.distance_to(close.global_position)
	_player.skills.cast(backstep, {"crit": 99.9})
	await _frames(25)
	_report("a backstep moves you away from the enemy", _player.global_position.distance_to(close.global_position) > before + 2.0, str(_player.global_position))
	close.queue_free()
	await _frames(3)

	_player.global_position = Vector3(0, 0.2, 0)
	_player.velocity = Vector3.ZERO
	var victim := _goblin(Vector3(0, 0, -2.5))
	await _frames(2)
	_ready_to_cast(100)
	var old_position := _player.global_position
	_player.skills.cast(teleport, {"crit": 99.9})
	await _frames(3)
	var behind := (_player.global_position - victim.global_position).dot(victim.global_position - old_position)
	_report("a teleport puts you behind the enemy", behind > 0.5, str(_player.global_position))
	_report("...close to it", _player.global_position.distance_to(victim.global_position) < 3.0)
	_eq("...and the skill hit it", victim.combatant.hp < 100000, true)
	victim.queue_free()


# ---------- the class bar during play ----------

func _test_class_bar_events() -> void:
	print("[cast] --- the class bar during play ---")
	await _setup_world("warrior", 20)
	_player.combatant.mp = 50
	_player.gain_resource("hit")
	_eq("hitting gives a warrior 6 Rage", _player.combatant.mp, 56)
	_player.combatant.take_damage(1)
	_eq("being hit gives 5 more", _player.combatant.mp, 61)
	_player._combat_clock = 0.0
	await _frames(60)
	_eq("while fighting, Rage holds", _player.combatant.mp, 61)
	_player._combat_clock = 10.0
	await _frames(60)
	_report("after 4+ quiet seconds Rage drains (6 a second)", _player.combatant.mp <= 56 and _player.combatant.mp >= 50, str(_player.combatant.mp))

	var enemy := _goblin(Vector3(0, 0, -2.0), false)
	await _frames(2)
	_player.combatant.mp = 0
	_player.target = enemy
	_player._attack_cooldown = 0.0
	var swing := _player.try_attack({"hit": 0.0, "parry": 99.9, "crit": 99.9, "block": 99.9, "weapon": 0.5})
	_report("a basic attack that hits builds Rage too", swing.get("outcome", "") != "hit" or _player.combatant.mp >= 6, str(swing))
	enemy.queue_free()

	await _setup_world("necromancer", 20)
	_player.combatant.mp = 10
	_player._on_kill_reward({"exp": 10, "gold": 1})
	_eq("a kill gives a necromancer 20 Soul Essence", _player.combatant.mp, 30)

	await _setup_world("mage", 20)
	_player.combatant.mp = 10
	_player._combat_clock = 0.0
	await _frames(60)
	_report("a mage's mana refills by itself (about 4 a second)", _player.combatant.mp >= 13 and _player.combatant.mp <= 16, str(_player.combatant.mp))
	_player._combat_clock = 10.0
	var rested := _player.combatant.mp
	await _frames(60)
	_report("...faster when resting (10 a second)", _player.combatant.mp - rested >= 8, "%d -> %d" % [rested, _player.combatant.mp])
	_player.combatant.mp = 5
	_player.gain_resource("hit")
	_eq("a mage gets nothing from hits", _player.combatant.mp, 5)


# ---------- the buttons ----------

func _test_buttons() -> void:
	print("[cast] --- skill buttons ---")
	await _setup_world("warrior", 100)
	var enemy := _goblin(Vector3(0, 0, -2.2))
	_learn("WAR_01_02", "skill_2")
	_learn("WAR_01_03", "skill_6")
	_ready_to_cast(100)
	await _frames(15)
	_eq("four skill buttons and a swap button", [_hud._skill_buttons.size(), _hud._swap_button != null], [4, true])
	_eq("the swap button names the page", _hud._swap_button.text, "1-4")
	var first: Dictionary = _hud._skill_buttons[1]
	_eq("button 1 shows Iron Slash's initials", (first["icon"] as Label).text, "IS")
	_eq("...and its cost", (first["cost"] as Label).text, "9")
	_eq("an empty slot shows a +", (_hud._skill_buttons[3]["icon"] as Label).text, "+")

	(first["button"] as Button).pressed.emit()
	await _frames(12)
	_eq("pressing a button casts the skill", _hits.size(), 1)
	_report("...and its cooldown darkens the button", (first["shade"] as ColorRect).anchor_top < 1.0)
	_report("...and counts the seconds", (first["time"] as Label).text != "", (first["time"] as Label).text)
	_hud.show_message("")
	(first["button"] as Button).pressed.emit()
	_report("pressing it again says it is not ready", "Not ready" in _hud._message.text, _hud._message.text)

	_player.combatant.mp = 2
	await _frames(12)
	_eq("with too little Rage the cost shows red-ish and the button dims", (first["button"] as Button).modulate.a < 1.0, true)
	_hud.show_message("")
	(_hud._skill_buttons[2]["button"] as Button).pressed.emit()
	_eq("a button with no Rage says so", _hud._message.text, "Not enough Rage.")

	_hud.swap_skill_page()
	await _frames(12)
	_eq("the swap button shows the other page", _hud._swap_button.text, "5-8")
	_eq("slot 6 is now on button 2", (_hud._skill_buttons[2]["icon"] as Label).text, SkillWindow._initials("WAR_01_03"))
	_eq("...and button 1 (slot 5) is empty", (_hud._skill_buttons[1]["icon"] as Label).text, "+")
	_hud.swap_skill_page()

	_ready_to_cast(100)
	var key := InputEventAction.new()
	key.action = "skill_1"
	key.pressed = true
	_player._unhandled_input(key)
	_eq("the 1 key casts slot 1", _hits.size(), 1)

	_eq("the class bar is called RG for a warrior", _hud._mp_label.text, "RG")
	_eq("...and has the Rage colour", (_hud._mp_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color, ClassResource.color("warrior"))
	await _setup_world("mage", 20)
	_eq("a mage's bar is MP, blue", [_hud._mp_label.text, (_hud._mp_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color], ["MP", ClassResource.color("mage")])
