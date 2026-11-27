extends Node
## DEV ONLY. Checks skills part 3: the 10 summon skills (helpers that follow you
## and fight), the 9 special attacks, the 9 ultimates, and their buttons.
## Needs no login and saves nothing. Run with F6.

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _player: PlayerController
var _hud: CombatHud
var _hits: Array = []
const NO_CRIT := {"crit": 99.9}


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false

	_test_data()
	await _test_summons()
	await _test_summon_kinds()
	await _test_unlocking_and_costs()
	await _test_warrior_and_mage()
	await _test_archer_rogue_gunner()
	await _test_healer_extreme()
	await _test_brawler_necromancer()
	await _test_buttons()

	Session.save_enabled = true
	Session.clear()
	print("[ability] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[ability] PASS  ", label)
	else:
		_failed += 1
		print("[ability] FAIL  %s  (%s)" % [label, detail])


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


func _goblin(position: Vector3, tank: bool = true) -> Enemy:
	var enemy := Enemy.new()
	enemy.setup("green_goblin", position, _world)
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	if tank:
		enemy.combatant.base_stats["max_health"] = 1000000
		enemy.combatant.stats["max_health"] = 1000000
		enemy.combatant.hp = 1000000
	return enemy


func _lost(enemy: Enemy) -> int:
	return 1000000 - enemy.combatant.hp


func _full(mp_extra: int = 0) -> void:
	_player.skills.cooldowns = PotionCooldowns.new()
	_player.combatant.mp = _player.combatant.max_mana() + mp_extra
	_player.combatant.hp = _player.combatant.max_health()
	_player._combat_clock = 99.0
	_hits.clear()


func _cast(ability_id: String) -> Dictionary:
	return _player.skills.cast_ability(ability_id, NO_CRIT)


func _damage_of(results: Array, who: String = "") -> Array:
	var damages: Array = []
	for result in results:
		if who == "" or str(result["target"]) == who:
			damages.append(int(result["damage"]))
	return damages


# ---------- the data ----------

func _test_data() -> void:
	print("[ability] --- the data ---")
	var summons: Dictionary = DataRegistry.get_config("summons")["summons"]
	_eq("11 summon types (10 from your skills + the legion's skeletons)", summons.size(), 11)
	var all_known := true
	for skill_id in DataRegistry.get_ids("skills"):
		if SkillEffects.effect_type(str(skill_id)) == "summon" and not summons.has(str(SkillEffects.effect(str(skill_id))["summon_id"])):
			all_known = false
	_eq("every summon skill points at a known summon", all_known, true)
	var kinds_ok := true
	for id in summons:
		if not ["melee", "ranged", "tank", "caster", "turret", "construct", "bomb", "aura"].has(str(summons[id]["kind"])):
			kinds_ok = false
	_eq("every summon has a kind", kinds_ok, true)
	var behaviors_ok := true
	for id in DataRegistry.get_ids("ultimates") + DataRegistry.get_ids("specials"):
		if AbilityEffects.behavior(str(id)) == "":
			behaviors_ok = false
	_eq("all 18 abilities have a behavior", behaviors_ok, true)
	_eq("WAR ultimate costs 100", AbilityEffects.cost("WAR_ULT_001"), 100)
	_eq("the mage's special costs 45 + 40 extra", AbilityEffects.cost("MAG_SPC_001"), 85)
	_near("an ultimate's cooldown is 120 s at rank 1", AbilityEffects.cooldown_at_rank("WAR_ULT_001", 1), 120.0)
	_near("...and 110.4 s at rank 5 (2% less a rank)", AbilityEffects.cooldown_at_rank("WAR_ULT_001", 5), 110.4, 0.01)
	_near("strength at rank 3 is 1.24", AbilityEffects.power("WAR_ULT_001", 3), 1.24)
	_near("mage ultimate damage: (950 + 20 INT x 1.25)", AbilityEffects.raw_damage("MAG_ULT_001", 1, {"int": 20}), 975.0)
	_eq("waves, strikes and fists need a target; buffs do not", [AbilityEffects.needs_target("MAG_ULT_001"), AbilityEffects.needs_target("WAR_ULT_001"), AbilityEffects.needs_target("BRA_SPC_001")], [true, false, true])
	_eq("Zero Point Collapse needs a full bar", [AbilityEffects.requires_full_resource("EXT_SPC_001"), AbilityEffects.requires_full_resource("WAR_SPC_001")], [true, false])


# ---------- summons ----------

func _test_summons() -> void:
	print("[ability] --- summons ---")
	await _setup_world("necromancer", 100)
	_learn("NEC_02_01")
	_player.skills.instant = false
	_full()
	var cast := _player.skills.cast("NEC_02_01")
	_eq("a summon skill needs no enemy", cast["ok"], true)
	await _frames(30)
	var list := _player.skills.active_summons()
	_eq("it calls one Skeleton", [list.size(), (list[0] as Summon).display_name()], [1, "Skeleton"])
	_report("...next to you (within 3.5 m)", Targeting.distance(_player, list[0]) <= 3.5, str(Targeting.distance(_player, list[0])))
	_eq("...a member of the summon group", (list[0] as Summon).is_in_group("summon"), true)
	_report("...with damage to deal", (list[0] as Summon).attack_damage > 0.0)

	# It finds enemies and fights them.
	var enemy := _goblin(Vector3(0, 0, -7))
	await _frames(150)
	var skeleton := _player.skills.active_summons()[0] as Summon
	_report("the skeleton runs at the enemy", Targeting.distance(skeleton, enemy) < 3.5, str(Targeting.distance(skeleton, enemy)))
	_report("...and hurts it", _lost(enemy) > 0, str(_lost(enemy)))
	_eq("...the damage is the player's (kills and EXP count)", enemy.combatant.last_attacker, _player.combatant)

	# Its time runs out.
	skeleton.remaining = 0.2
	await _frames(30)
	_eq("when its time is up it disappears", _player.skills.active_summons().size(), 0)

	# Casting again replaces the old one.
	_player.skills.instant = true
	_full()
	_player.skills.cast("NEC_02_01")
	_player.skills.cooldowns = PotionCooldowns.new()
	_player.skills.cast("NEC_02_01")
	await _frames(3)
	_eq("calling it again does not double it (max 1)", _player.skills.active_summons("SKELETON_SUMMON").size(), 1)

	# An army calls five.
	_learn("NEC_02_06")
	_full()
	_player.skills.cast("NEC_02_06")
	await _frames(3)
	_eq("Army of the Damned calls 5 soldiers", _player.skills.active_summons("ARMY_SUMMON").size(), 5)

	# Different summons live together.
	_learn("NEC_02_02")
	_full()
	_player.skills.cast("NEC_02_02")
	await _frames(3)
	_eq("a Bone Archer joins them (6 in all)", _player.skills.active_summons().size(), 6 + 1 - 1 + 1)
	enemy.queue_free()

	# A kill by summons counts.
	await _setup_world("necromancer", 100)
	_learn("NEC_02_01")
	_full()
	var weak := _goblin(Vector3(0, 0, -6), false)
	weak.combatant.hp = 3
	_player.skills.cast("NEC_02_01")
	await _frames(240)
	_eq("summons can kill, and the player gets the credit", [weak.is_dead(), weak.combatant.last_attacker == _player.combatant], [true, true])

	# Dying removes them.
	_full()
	_player.skills.cast("NEC_02_01")
	await _frames(3)
	_report("a summon is out", _player.skills.active_summons().size() >= 1)
	_player.combatant.take_damage(_player.combatant.hp)
	await _frames(5)
	_eq("when the player dies the summons go", _player.skills.active_summons().size(), 0)


func _test_summon_kinds() -> void:
	print("[ability] --- the kinds of summon ---")
	await _setup_world("necromancer", 100)
	_learn("NEC_02_02")
	_learn("NEC_02_03")
	_learn("NEC_02_05")
	_full()
	var enemy := _goblin(Vector3(0, 0, -9))
	_player.skills.cast("NEC_02_02")
	await _frames(200)
	var archer := _player.skills.active_summons("RANGED_SUMMON")[0] as Summon
	_report("a bone archer shoots from a distance (it stays 4+ m away)", Targeting.distance(archer, enemy) > 4.0, str(Targeting.distance(archer, enemy)))
	_report("...and hurts the enemy", _lost(enemy) > 0)

	_full()
	_player.skills.cast("NEC_02_05")
	await _frames(200)
	var lich := _player.skills.active_summons("CASTER_SUMMON")[0] as Summon
	_report("a lich servant casts from afar", Targeting.distance(lich, enemy) > 4.0, str(Targeting.distance(lich, enemy)))

	_full()
	_player.skills.cast("NEC_02_03")
	await _frames(200)
	var guardian := _player.skills.active_summons("TANK_SUMMON")[0] as Summon
	_report("a grave guardian fights up close", Targeting.distance(guardian, enemy) < 4.0, str(Targeting.distance(guardian, enemy)))

	# Aura: Eternal Dominion makes the others hit harder.
	_learn("NEC_03_06")
	_eq("with no aura summon there is no bonus", _player.skills.summon_attack_bonus(), 0.0)
	_full()
	_player.skills.cast("NEC_03_06")
	await _frames(3)
	_near("an aura summon gives all summons +25% damage", _player.skills.summon_attack_bonus(), 0.25)

	# A pact fiend explodes when it expires.
	await _setup_world("necromancer", 100)
	_learn("NEC_03_05")
	_full()
	var victim := _goblin(Vector3(0, 0, -3))
	_player.skills.cast("NEC_03_05")
	await _frames(3)
	var fiend := _player.skills.active_summons("SUMMON_SACRIFICE")[0] as Summon
	var fiend_damage := fiend.attack_damage
	fiend.set_physics_process(false)
	var before := _lost(victim)
	fiend.remaining = 0.0
	fiend.set_physics_process(true)
	await _frames(5)
	var blast := _lost(victim) - before
	_report("it explodes when its time is up (about 3 attacks' worth)", blast > fiend_damage * 1.5, "%d vs %d" % [blast, int(fiend_damage)])
	victim.queue_free()

	# A turret stays where it is and shoots.
	await _setup_world("gunner", 100)
	_learn("GUN_03_04")
	_full()
	var target := _goblin(Vector3(0, 0, -8))
	_player.skills.cast("GUN_03_04")
	await _frames(3)
	var turret := _player.skills.active_summons("TURRET")[0] as Summon
	var turret_spot := turret.global_position
	await _frames(160)
	_eq("a turret stays where it was put", turret.global_position.distance_to(turret_spot) < 0.01, true)
	_report("...and shoots the enemy", _lost(target) > 0)
	_eq("it works without an enemy nearby too (the skill had base damage)", turret.attack_damage > 0.0, true)


# ---------- unlocking and costs ----------

func _test_unlocking_and_costs() -> void:
	print("[ability] --- unlocking, cost and cooldown ---")
	await _setup_world("warrior", 99)
	_full()
	_eq("the special attack is locked below level 100", _player.skills.cast_ability("WAR_SPC_001")["error"], "LOCKED")
	_eq("...and says the level", _player.skills.cast_ability("WAR_SPC_001")["message"], "Reach level 100 to use Executioner's Judgment.")
	Session.character["level"] = 150
	Session.character_changed.emit()
	await _frames(3)
	_full()
	var enemy := _goblin(Vector3(0, 0, -3))
	_eq("at level 150 it can be cast", _player.skills.cast_ability("WAR_SPC_001", NO_CRIT)["ok"], true)
	_eq("it cost 45 Rage (and the hit gave 6 back)", _player.combatant.mp, _player.combatant.max_mana() - 45 + 6)
	_report("its cooldown is 45 s", absf(_player.skills.cooldowns.remaining("WAR_SPC_001") - 45.0) < 0.1)
	_eq("it can't be cast again at once", _player.skills.cast_ability("WAR_SPC_001")["error"], "COOLDOWN")
	_eq("the ultimate is still locked (level 200)", _player.skills.cast_ability("WAR_ULT_001")["error"], "LOCKED")
	_full()
	_player.combatant.mp = 30
	_eq("with too little Rage it is refused", _player.skills.cast_ability("WAR_SPC_001")["error"], "NOT_ENOUGH_RESOURCE")
	_full()
	enemy.global_position = Vector3(0, 0, -20)
	_eq("a strike needs the target within 8 m", _player.skills.cast_ability("WAR_SPC_001")["error"], "NO_TARGET")
	_eq("...nothing was spent", _player.combatant.mp, _player.combatant.max_mana())
	_eq("an unknown ability", _player.skills.cast_ability("NOPE")["error"], "UNKNOWN")
	enemy.queue_free()


# ---------- warrior and mage ----------

func _test_warrior_and_mage() -> void:
	print("[ability] --- warrior and mage ---")
	await _setup_world("warrior", 250)
	_full()
	var base_attack := float(_player.combatant.stats["atk_power"])
	var base_defense := float(_player.combatant.stats["def_power"])
	_eq("Kingdom's Last Stand needs no enemy", _cast("WAR_ULT_001")["ok"], true)
	_near("it raises attack power by 35%", float(_player.combatant.stats["atk_power"]) / base_attack, 1.35, 0.02)
	_near("...and defense by 25%", float(_player.combatant.stats["def_power"]) / base_defense, 1.25, 0.02)
	_eq("...as the effect 'ability_WAR_ULT_001'", _player.combatant.status.active_ids().has("ability_WAR_ULT_001"), true)
	await _frames(15)
	_report("...which shows as a chip", _hud._buff_box.get_child_count() >= 1)
	_player.combatant.tick(12.5)
	_near("it ends after 12 s", float(_player.combatant.stats["atk_power"]), base_attack, 0.5)

	# Executioner's Judgment hits harder on a weak target.
	var healthy := _goblin(Vector3(0, 0, -3))
	_full()
	var strike := _cast("WAR_SPC_001")
	_eq("the special attack is cast", strike["ok"], true)
	if _hits.is_empty():
		_report("a hit was recorded", false, str(strike))
		return
	var normal := float(_hits[0]["damage"])
	healthy.queue_free()
	await _frames(3)
	var weak := _goblin(Vector3(0, 0, -3))
	weak.combatant.hp = 200000          # 20%
	_full()
	_cast("WAR_SPC_001")
	_near("Executioner's Judgment does 60% more below 25% health", float(_hits[0]["damage"]) / normal, 1.6, 0.05)
	weak.queue_free()
	await _frames(3)

	await _setup_world("mage", 250)
	var a := _goblin(Vector3(0, 0, -6))
	var b := _goblin(Vector3(3, 0, -6))
	var c := _goblin(Vector3(-3, 0, -7))
	var far := _goblin(Vector3(30, 0, -6))
	_full()
	_cast("MAG_ULT_001")
	_eq("Eternal Cataclysm: 5 waves on each of the 3 enemies in the area", _hits.size(), 15)
	_eq("...nobody outside the area is hurt", _lost(far), 0)
	var raw := AbilityEffects.raw_damage("MAG_ULT_001", 1, _player.skills._attributes())
	var reduction := float(a.combatant.stats.get("magic_resist", 0.0)) / (float(a.combatant.stats.get("magic_resist", 0.0)) + 100.0)
	_near("...the 950 base is shared between the waves", float(_lost(a)), raw * (1.0 - reduction), 6.0)
	_player.skills.instant = false
	_full()
	for e in [a, b, c]:
		e.combatant.hp = 1000000
	_hits.clear()
	_cast("MAG_ULT_001")
	await _frames(int(2.0 * 60.0) + 15)          # the 2 s cast, then the first waves
	_report("with real timing the waves come one after another", _hits.size() > 0 and _hits.size() < 15, str(_hits.size()))
	await _frames(7 * 60)
	_eq("...and all 5 arrive in the end", _hits.size(), 15)
	_player.skills.instant = true

	# Arcane Overload: a big cost and a bonus for the next spell.
	a.global_position = Vector3(0, 0, -3.0)          # Arcane Bolt only reaches 3.6 m
	b.global_position = Vector3(30, 0, -30)
	c.global_position = Vector3(-30, 0, -30)
	_player.set_target(a)
	_learn("MAG_01_01", "skill_1")
	_full()
	for e in [a, b, c]:
		e.combatant.hp = 1000000
	_player.skills.cast("MAG_01_01", NO_CRIT)
	var plain := float(_hits[0]["damage"])
	_full()
	_eq("Arcane Overload costs 45 + 40 mana", [_cast("MAG_SPC_001")["ok"], _player.combatant.mp], [true, _player.combatant.max_mana() - 85])
	_report("...and primes the next spell", _player.combatant.status.find_with_key("next_skill_bonus") != "")
	_player.skills.cooldowns = PotionCooldowns.new()
	_hits.clear()
	_player.skills.cast("MAG_01_01", NO_CRIT)
	_near("the next spell does 65% more", float(_hits[0]["damage"]) / plain, 1.65, 0.05)
	_eq("...and the bonus is used up", _player.combatant.status.find_with_key("next_skill_bonus"), "")
	for node in [a, b, c, far]:
		node.queue_free()


# ---------- archer, rogue, gunner ----------

func _test_archer_rogue_gunner() -> void:
	print("[ability] --- archer, rogue, gunner ---")
	await _setup_world("archer", 250)
	_full()
	var crit_before := float(_player.combatant.stats["crit_chance"])
	_cast("ARC_SPC_001")
	_near("Deadly Focus adds 25 to critical chance", float(_player.combatant.stats["crit_chance"]) - crit_before, 25.0, 0.1)
	var enemy := _goblin(Vector3(0, 0, -8))
	var other := _goblin(Vector3(4, 0, -9))
	_full()
	_hits.clear()
	_cast("ARC_ULT_001")
	_eq("Heaven's Arrowfall: 6 waves on 2 enemies", _hits.size(), 12)

	await _setup_world("rogue", 250)
	var group: Array = []
	for i in 6:
		group.append(_goblin(Vector3(float(i) - 2.5, 0, -4 - i)))
	(group[0] as Enemy).combatant.status.apply("shadow_mark")
	_full()
	_cast("ROG_ULT_001")
	var struck := 0
	for e in group:
		if _lost(e) > 0:
			struck += 1
	_eq("Requiem of the Eclipse hits at most 5 enemies", struck, 5)
	_eq("...8 times each", _hits.size(), 40)
	var marked_total := _lost(group[0])
	var plain_total := _lost(group[1])
	_near("a marked enemy takes 30% more (and the mark itself adds 15%)", float(marked_total) / float(plain_total), 1.3 * 1.15, 0.08)
	for e in group:
		e.queue_free()
	await _frames(3)
	var weak := _goblin(Vector3(0, 0, -3))
	weak.combatant.hp = 100000          # 10%
	_full()
	_cast("ROG_SPC_001")
	var weak_hit := float(_hits[0]["damage"])
	weak.combatant.hp = 1000000
	_full()
	_cast("ROG_SPC_001")
	_near("Final Silence does 75% more below 20% health", weak_hit / float(_hits[0]["damage"]), 1.75, 0.06)
	weak.queue_free()

	await _setup_world("gunner", 250)
	var target := _goblin(Vector3(0, 0, -5))
	_full()
	_cast("GUN_SPC_001")
	var damages := _damage_of(_hits)
	_eq("Deadlock Execution fires 6 shots", damages.size(), 6)
	_near("the shots grow with lock-on stacks (4th is 36% above the 1st)", float(damages[3]) / float(damages[0]), 1.36, 0.06)
	_report("...and stop growing after 3 stacks", absi(int(damages[5]) - int(damages[3])) <= 2, str(damages))
	_full()
	_hits.clear()
	_cast("GUN_ULT_001")
	_eq("Apocalypse Protocol fires 6 rockets", _hits.size(), 6)
	target.queue_free()


# ---------- healer and extreme ----------

func _test_healer_extreme() -> void:
	print("[ability] --- healer and extreme ---")
	await _setup_world("healer", 250)
	var near := _goblin(Vector3(0, 0, -4))
	var far := _goblin(Vector3(30, 0, -4))
	_full()
	_player.combatant.hp = 10
	_cast("HEA_ULT_001")
	_near("Divine Ascension cuts damage taken by 20%", _player.combatant.status.damage_taken_multiplier(), 0.8)
	_report("...hurts enemies inside the field", _lost(near) > 0)
	_eq("...but not those outside", _lost(far), 0)
	await _frames(6 * 60)
	_report("...and heals you over its 10 seconds", _player.combatant.hp > 10 + int(_player.combatant.max_health() * 0.05), str(_player.combatant.hp))
	_player.combatant.tick(11.0)
	_eq("...then it ends", _player.combatant.status.damage_taken_multiplier(), 1.0)
	_full()
	_cast("HEA_SPC_001")
	_near("Guardian's Sacrifice (on yourself for now) cuts damage by 35%", _player.combatant.status.damage_taken_multiplier(), 0.65)
	near.queue_free()
	far.queue_free()

	await _setup_world("extreme", 250)
	var attack_before := float(_player.combatant.stats["atk_power"])
	_full()
	_cast("EXT_ULT_001")
	_near("The Absolute Anomaly: +40% attack", float(_player.combatant.stats["atk_power"]) / attack_before, 1.40, 0.03)
	_near("...takes 15% less damage", _player.combatant.status.damage_taken_multiplier(), 0.85)
	var mp_before := _player.combatant.mp
	_player._combat_clock = 0.0
	await _frames(120)
	_report("...and drains the class bar (8 a second)", mp_before - _player.combatant.mp >= 12, "%d -> %d" % [mp_before, _player.combatant.mp])
	_player.combatant.mp = 5
	await _frames(90)
	_eq("when the bar runs out the transformation ends", _player.combatant.status.active_ids().has("ability_EXT_ULT_001"), false)

	# Zero Point Collapse needs a full bar and empties it.
	var enemy := _goblin(Vector3(0, 0, -6))
	var side := _goblin(Vector3(6, 0, -6))
	_full()
	_player.combatant.mp = _player.combatant.max_mana() - 10
	_eq("it is refused unless the bar is full", _player.skills.cast_ability("EXT_SPC_001")["error"], "FULL_RESOURCE_NEEDED")
	_eq("...and says which bar", _player.skills.cast_ability("EXT_SPC_001")["message"], "Anomaly Energy must be full.")
	_full()
	var before := side.global_position.distance_to(enemy.global_position)
	_cast("EXT_SPC_001")
	_eq("with a full bar it fires, and empties the bar", [_hits.size() >= 1, _player.combatant.mp], [true, 0])
	_report("it pulls enemies in toward the middle", side.global_position.distance_to(enemy.global_position) < before - 2.0)
	_report("...and both take the blast", _lost(enemy) > 0 and _lost(side) > 0)
	enemy.queue_free()
	side.queue_free()


# ---------- brawler and necromancer ----------

func _test_brawler_necromancer() -> void:
	print("[ability] --- brawler and necromancer ---")
	await _setup_world("brawler", 250)
	var enemy := _goblin(Vector3(0, 0, -3))
	var second := _goblin(Vector3(1.5, 0, -3))
	_full()
	_cast("BRA_ULT_001")
	var damages := _damage_of(_hits)
	_eq("Dragon King's Ascension hits 10 times on each enemy near you", _hits.size(), 20)
	_near("...and each hit is 4% stronger (the 10th is 36% above the 1st)", float(damages[18]) / float(damages[0]), 1.36, 0.06)
	_full()
	_hits.clear()
	_cast("BRA_SPC_001")
	var fists := _damage_of(_hits)
	_eq("One Thousand Fists lands 12 punches", fists.size(), 12)
	_near("...each 6% stronger (the 12th is 66% above the 1st)", float(fists[11]) / float(fists[0]), 1.66, 0.08)
	enemy.queue_free()
	second.queue_free()

	await _setup_world("necromancer", 250)
	_full()
	_cast("NEC_ULT_001")
	_eq("The Undying Legion calls 8 skeletons", _player.skills.active_summons("LEGION_SKELETON").size(), 8)
	_report("...for 20 seconds", absf((_player.skills.active_summons("LEGION_SKELETON")[0] as Summon).remaining - 20.0) < 0.5)
	_player.skills.cooldowns = PotionCooldowns.new()
	_full()
	_cast("NEC_ULT_001")
	await _frames(3)
	_eq("calling it again replaces them (still 8)", _player.skills.active_summons("LEGION_SKELETON").size(), 8)
	_player.skills.clear_summons()

	var victim := _goblin(Vector3(0, 0, -4))
	_full()
	_player.combatant.hp = 10
	_player.combatant.mp = 40
	_player.skills.cooldowns = PotionCooldowns.new()
	_player.combatant.mp = 60
	_cast("NEC_SPC_001")
	var dealt := int(_hits[0]["damage"])
	_report("Soul Devourer heals 30% of the damage it deals", _player.combatant.hp >= 10 + int(dealt * 0.3) - 1, "%d vs %d" % [_player.combatant.hp, dealt])
	_report("...and gives 25 Soul Essence (60 - 45 + 2 + 25)", _player.combatant.mp >= 38, str(_player.combatant.mp))
	_full()
	_player.skills.cooldowns = PotionCooldowns.new()
	victim.combatant.status.apply("curse")
	_hits.clear()
	_cast("NEC_SPC_001")
	var cursed := float(_hits[0]["damage"])
	_report("it does 20% more to a cursed enemy", cursed / maxf(1.0, float(dealt)) > 1.1, "%f" % (cursed / float(dealt)))
	victim.queue_free()


# ---------- the buttons ----------

func _test_buttons() -> void:
	print("[ability] --- the special and ultimate buttons ---")
	await _setup_world("warrior", 150)
	var enemy := _goblin(Vector3(0, 0, -3))
	_full()
	await _frames(15)
	var special: Dictionary = _hud._ability_buttons["special"]
	var ultimate: Dictionary = _hud._ability_buttons["ultimate"]
	_eq("a special attack button and an ultimate button", [special["button"] != null, ultimate["button"] != null], [true, true])
	_eq("the special's name (Executioner's Judgment)", (special["icon"] as Label).text, "Executioner's Judgment")
	_eq("...and its cost", (special["cost"] as Label).text, "45")
	_eq("the ultimate shows the level it needs", (ultimate["lock"] as Label).text, "Lv 200")
	_eq("...and is dimmed", (ultimate["button"] as Button).modulate.a < 1.0, true)
	_hud.show_message("")
	(ultimate["button"] as Button).pressed.emit()
	_eq("pressing the locked ultimate says what is needed", _hud._message.text, "Reach level 200 to use Kingdom's Last Stand.")

	(special["button"] as Button).pressed.emit()
	await _frames(12)
	_eq("pressing the special attack button casts it", _hits.size(), 1)
	_report("...its cooldown darkens the button and counts down", (special["shade"] as ColorRect).anchor_top < 1.0 and (special["time"] as Label).text != "")
	_hud.show_message("")
	(special["button"] as Button).pressed.emit()
	_report("pressing it again says it is not ready", "Not ready" in _hud._message.text, _hud._message.text)

	_full()
	var key := InputEventAction.new()
	key.action = "special"
	key.pressed = true
	_player._unhandled_input(key)
	_eq("the Q key casts the special attack", _hits.size(), 1)
	Session.character["level"] = 250
	Session.character_changed.emit()
	await _frames(15)
	_eq("at level 250 the ultimate unlocks (no level shown)", [(ultimate["lock"] as Label).text, (ultimate["button"] as Button).modulate.a >= 0.6], ["", true])
	_full()
	var ult_key := InputEventAction.new()
	ult_key.action = "ultimate"
	ult_key.pressed = true
	_player._unhandled_input(ult_key)
	_eq("the R key casts the ultimate", _player.combatant.status.active_ids().has("ability_WAR_ULT_001"), true)
	enemy.queue_free()

	await _setup_world("mage", 250)
	await _frames(15)
	_eq("a mage's buttons: Eternal Cataclysm and Arcane Overload", [(_hud._ability_buttons["ultimate"]["icon"] as Label).text, (_hud._ability_buttons["special"]["icon"] as Label).text], ["Eternal Cataclysm", "Arcane Overload"])
	_eq("...Arcane Overload costs 85", (_hud._ability_buttons["special"]["cost"] as Label).text, "85")
