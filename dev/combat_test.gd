extends Node
## DEV ONLY. Fixed scenarios for the combat logic (M5): damage math, elements,
## status effects, combatants and the resolver. The numbers are fixed with set
## "rolls", so the results are the same every time. Run with F6 and read the
## Output panel. The expected numbers use the placeholder rules in
## TSM_Combat_Rules.json and TSM_Element_Rules.json: if you change those, update
## the numbers here.

var _passed: int = 0
var _failed: int = 0

const SURE_HIT := {"hit": 0.0, "parry": 99.9, "crit": 99.9, "block": 99.9, "weapon": 0.5}


func _ready() -> void:
	await get_tree().process_frame
	_test_data()
	_test_damage_math()
	_test_elements()
	_test_status_effects()
	_test_combatant()
	_test_resolver()
	_test_profiles_and_enemy_stats()
	print("[combat] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float) -> void:
	_report(label, absf(got - expected) < 0.011, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[combat] PASS  ", label)
	else:
		_failed += 1
		print("[combat] FAIL  %s  (%s)" % [label, detail])


func _rolls(overrides: Dictionary = {}) -> Dictionary:
	var rolls := SURE_HIT.duplicate()
	rolls.merge(overrides, true)
	return rolls


# Attacker: atk 21, magic 26, accuracy 90, crit 5% / 150%, weapon 10..18.
func _attacker(extra_stats: Dictionary = {}, weapon: Dictionary = {"min": 10, "max": 18}, skill: float = 1.0) -> Dictionary:
	var stats := {"atk_power": 21, "magic_power": 26, "accuracy": 90.0, "crit_chance": 5.0, "crit_damage": 150.0}
	stats.merge(extra_stats, true)
	return {"stats": stats, "weapon": weapon, "skill_multiplier": skill}


func _defender(stats: Dictionary = {}, profile: Dictionary = {}, taken: float = 1.0) -> Dictionary:
	return {"stats": stats, "profile": profile, "damage_taken_multiplier": taken}


func _fighter(p_name: String, stats: Dictionary, p_team: String = "") -> Combatant:
	var fighter := Combatant.new()
	fighter.setup(p_name, 1, stats, p_team)
	return fighter


# ---------- tests ----------

func _test_data() -> void:
	print("[combat] --- data ---")
	_eq("combat_rules loaded", DataRegistry.get_config("combat_rules").is_empty(), false)
	_eq("element_rules loaded", DataRegistry.get_config("element_rules").is_empty(), false)
	_report("at least 20 status effects", DataRegistry.get_ids("status_effects").size() >= 20,
			"found %d" % DataRegistry.get_ids("status_effects").size())
	_eq("status effect data has no problems", StatusEffectManager.validate(), [])
	for problem in StatusEffectManager.validate():
		print("[combat] PROBLEM ", problem)
	var unknown := ElementalSystem.unknown_enemy_elements()
	print("[combat] note  elements used by enemies that the chart does not know yet (treated as neutral): %s" % str(unknown))
	var missing_effects: Array = []
	for enemy_id in DataRegistry.get_ids("enemies"):
		for token in str(DataRegistry.get_enemy(enemy_id).get("status_EFF", "")).split(","):
			var cleaned := token.strip_edges()
			if cleaned != "" and cleaned != "N/A" and StatusEffectManager.resolve_id(cleaned) == "" and not missing_effects.has(cleaned):
				missing_effects.append(cleaned)
	print("[combat] note  status effects named in the enemy data that have no definition yet: %s" % str(missing_effects))


func _test_damage_math() -> void:
	print("[combat] --- damage math ---")
	var hit := DamageCalculator.resolve(_attacker(), _defender(), _rolls())
	_eq("plain hit: outcome", hit["outcome"], "hit")
	_eq("plain hit: weapon 14 + attack 21 = 35", hit["damage"], 35)
	_eq("plain hit: not a crit", hit["is_crit"], false)

	_eq("weapon roll 0.0 is the minimum (10 + 21)", DamageCalculator.resolve(_attacker(), _defender(), _rolls({"weapon": 0.0}))["damage"], 31)
	_eq("weapon roll 0.999 is the maximum (18 + 21)", DamageCalculator.resolve(_attacker(), _defender(), _rolls({"weapon": 0.999}))["damage"], 39)
	_eq("bare hands: 1..3 plus attack", DamageCalculator.resolve(_attacker({}, {}), _defender(), _rolls({"weapon": 0.0}))["damage"], 22)
	_eq("skill multiplier 2 doubles it", DamageCalculator.resolve(_attacker({}, {"min": 10, "max": 18}, 2.0), _defender(), _rolls())["damage"], 70)

	_eq("defense 100 takes half off", DamageCalculator.resolve(_attacker(), _defender({"def_power": 100}), _rolls())["damage"], 17)
	_eq("defense reduction is capped at 90%", DamageCalculator.resolve(_attacker(), _defender({"def_power": 1000000}), _rolls())["damage"], 3)
	_eq("a hit always does at least 1", DamageCalculator.resolve(_attacker({"atk_power": 0}, {"min": 1, "max": 1}), _defender({"def_power": 1000000}), _rolls())["damage"], 1)

	var crit := DamageCalculator.resolve(_attacker(), _defender(), _rolls({"crit": 0.0}))
	_eq("crit: 35 x 1.5", crit["damage"], 52)
	_eq("crit is flagged", crit["is_crit"], true)
	_eq("a crit roll equal to the chance is not a crit", DamageCalculator.resolve(_attacker(), _defender(), _rolls({"crit": 5.0}))["is_crit"], false)

	var blocked := DamageCalculator.resolve(_attacker(), _defender({"block_rate": 100, "block_mitigation": 50}), _rolls())
	_eq("block with 50% mitigation halves it", blocked["damage"], 17)
	_eq("block is flagged", blocked["blocked"], true)
	_eq("crit and block together: 35 x 1.5 x 0.5", DamageCalculator.resolve(_attacker(), _defender({"block_rate": 100, "block_mitigation": 50}), _rolls({"crit": 0.0}))["damage"], 26)
	_eq("'takes 15% more damage' effect", DamageCalculator.resolve(_attacker(), _defender({}, {}, 1.15), _rolls())["damage"], 40)

	var miss := DamageCalculator.resolve(_attacker(), _defender(), _rolls({"hit": 99.0}))
	_eq("a high hit roll misses", miss["outcome"], "miss")
	_eq("a miss does no damage", miss["damage"], 0)
	_near("hit chance is accuracy minus evasion", DamageCalculator.resolve(_attacker(), _defender({"evasion": 50}), _rolls())["hit_chance"], 40.0)
	_eq("roll just under the hit chance hits", DamageCalculator.resolve(_attacker(), _defender({"evasion": 50}), _rolls({"hit": 39.9}))["outcome"], "hit")
	_eq("roll equal to the hit chance misses", DamageCalculator.resolve(_attacker(), _defender({"evasion": 50}), _rolls({"hit": 40.0}))["outcome"], "miss")
	_near("hit chance never drops below 5%", DamageCalculator.resolve(_attacker({"accuracy": 0}), _defender({"evasion": 100}), _rolls())["hit_chance"], 5.0)
	_near("hit chance never goes above 100%", DamageCalculator.resolve(_attacker({"accuracy": 500}), _defender(), _rolls())["hit_chance"], 100.0)

	var parried := DamageCalculator.resolve(_attacker(), _defender({"parry_rate": 100}), _rolls({"parry": 0.0}))
	_eq("a parry turns the attack aside", parried["outcome"], "parry")
	_eq("...and does no damage", parried["damage"], 0)

	var magic := {"min": 10, "max": 18, "stat": "magic_power"}
	_eq("a magic weapon uses magic power: 14 + 26", DamageCalculator.resolve(_attacker({}, magic), _defender(), _rolls())["damage"], 40)
	_eq("...and magic resist, not defense", DamageCalculator.resolve(_attacker({}, magic), _defender({"def_power": 1000, "magic_resist": 100}), _rolls())["damage"], 20)

	var seeded := RandomNumberGenerator.new()
	seeded.seed = 7
	var hits := 0
	for i in 10000:
		if DamageCalculator.resolve(_attacker(), _defender(), {}, seeded)["outcome"] == "hit":
			hits += 1
	_report("90 accuracy hits about 90% of the time (10,000 swings)", hits >= 8800 and hits <= 9200, "%d hits" % hits)

	# Element damage on the weapon.
	var fire_weapon := {"min": 10, "max": 18, "element": "Fire", "element_amount": 25.0}
	var neutral := DamageCalculator.resolve(_attacker({}, fire_weapon), _defender(), _rolls())
	_eq("fire weapon vs neutral: 35 + 25", neutral["damage"], 60)
	_eq("...elemental part is 25", neutral["elemental"], 25)
	_eq("fire vs a water target (resists fire): 35 + 12.5", DamageCalculator.resolve(_attacker({}, fire_weapon), _defender({}, ElementalSystem.profile_for("Water")), _rolls())["damage"], 47)
	_eq("fire vs a nature target (weak to fire): 35 + 37.5", DamageCalculator.resolve(_attacker({}, fire_weapon), _defender({}, ElementalSystem.profile_for("Nature")), _rolls())["damage"], 72)
	_eq("fire vs an immune target: only the 35", DamageCalculator.resolve(_attacker({}, fire_weapon), _defender({}, {"immune": ["fire"]}), _rolls())["damage"], 35)


func _test_elements() -> void:
	print("[combat] --- elements ---")
	_eq("Shadow/Fire is two elements", ElementalSystem.canonical("Shadow/Fire"), ["dark", "fire"])
	_eq("Lightning is shock", ElementalSystem.canonical("Lightning"), ["shock"])
	_eq("Cursed Fire is fire", ElementalSystem.canonical("Cursed Fire"), ["fire"])
	_eq("Lunar Shadow is dark (lunar unknown)", ElementalSystem.canonical("Lunar Shadow"), ["dark"])
	_eq("N/A is no element", ElementalSystem.canonical("N/A"), [])
	_eq("case does not matter", ElementalSystem.canonical("FIRE"), ["fire"])

	var nature := ElementalSystem.profile_for("Nature")
	_eq("fire hurts nature", ElementalSystem.multiplier("Fire", nature), 1.5)
	_eq("water is resisted by nature", ElementalSystem.multiplier("Water", nature), 0.5)
	_eq("shock is neutral against nature", ElementalSystem.multiplier("Shock", nature), 1.0)
	_eq("physical is always neutral", ElementalSystem.multiplier("Physical", nature), 1.0)
	_eq("holy hurts dark", ElementalSystem.multiplier("Holy", ElementalSystem.profile_for("Dark")), 1.5)
	_eq("an unknown target element is neutral", ElementalSystem.multiplier("Fire", ElementalSystem.profile_for("Lunar")), 1.0)
	_eq("an unknown attack element is neutral", ElementalSystem.multiplier("Plasma", nature), 1.0)
	_eq("immune wins", ElementalSystem.multiplier("Fire", {"immune": ["fire"], "weak": ["fire"]}), 0.0)

	var mixed := ElementalSystem.profile_for("Fire/Water")
	_eq("weak and resistant cancel out (water vs fire/water)", ElementalSystem.multiplier("Water", mixed), 1.0)
	_eq("what is left stays (shock vs fire/water)", ElementalSystem.multiplier("Shock", mixed), 1.5)

	var beast := ElementalSystem.profile_for_enemy("blackthorn_dreadbeast")
	_eq("Blackthorn (Corrupted Nature) counts as nature", beast["elements"], ["nature"])
	_eq("...so fire hurts it", ElementalSystem.multiplier("Fire", beast), 1.5)
	_eq("the training dummy has no element", ElementalSystem.profile_for_enemy("training_dummy")["elements"], [])
	_eq("an unknown enemy has no element", ElementalSystem.profile_for_enemy("not_an_enemy")["elements"], [])


func _test_status_effects() -> void:
	print("[combat] --- status effects ---")
	_eq("names resolve to ids", StatusEffectManager.resolve_id("Armor Break"), "armor_break")
	_eq("aliases resolve (Weaken)", StatusEffectManager.resolve_id("Weaken"), "weakness")
	_eq("aliases resolve (Chill)", StatusEffectManager.resolve_id("Chill"), "chilled")
	_eq("unknown names resolve to nothing", StatusEffectManager.resolve_id("Plasma Burn"), "")

	var manager := StatusEffectManager.new()
	_eq("an unknown effect is refused", manager.apply("Plasma Burn")["ok"], false)

	var poison := manager.apply("Poison")
	_eq("poison starts at 1 stack", poison["stacks"], 1)
	var events := manager.update(1.0, 10000.0)
	_eq("1 second gives 1 tick", events.size(), 1)
	_near("poison ticks 0.6% of max health", events[0]["amount"], 60.0)
	_eq("it is damage", events[0]["kind"], "damage")
	manager.apply("Poison")
	manager.apply("Poison")
	_eq("poison stacks", manager.stacks("poison"), 3)
	_near("3 stacks tick 3 times as hard", manager.update(1.0, 10000.0)[0]["amount"], 180.0)
	for i in 5:
		manager.apply("Poison")
	_eq("poison stops at 5 stacks", manager.stacks("poison"), 5)

	manager = StatusEffectManager.new()
	manager.apply("Poison")
	var all_ticks := manager.update(8.0, 10000.0)
	_eq("poison lasts 8 seconds and ticks 8 times", all_ticks.size(), 8)
	_eq("then it is gone", manager.has("poison"), false)

	manager = StatusEffectManager.new()
	manager.apply("Burn")
	manager.update(3.0, 1000.0)
	_near("burn has 2 seconds left after 3", manager.remaining("burn"), 2.0)
	manager.apply("Burn")
	_near("applying it again restarts the timer", manager.remaining("burn"), 5.0)
	_eq("burn does not stack", manager.stacks("burn"), 1)

	manager = StatusEffectManager.new()
	manager.apply("Slow")
	_near("slow cuts speed by 35%", StatCalculator.apply_modifiers({"move_speed": 7.0}, manager.modifiers())["move_speed"], 4.55)
	manager = StatusEffectManager.new()
	for i in 3:
		manager.apply("Armor Break")
	_eq("armor break stacks to -30% defense", StatCalculator.apply_modifiers({"def_power": 100}, manager.modifiers())["def_power"], 70)
	_eq("a stat the target does not have is ignored", StatCalculator.apply_modifiers({"atk_power": 10}, manager.modifiers())["atk_power"], 10)

	manager = StatusEffectManager.new()
	manager.apply("Stun")
	_eq("stun: cannot move", manager.can_move(), false)
	_eq("stun: cannot attack", manager.can_attack(), false)
	_eq("stun: cannot cast", manager.can_cast(), false)
	manager.update(2.0, 100.0)
	_eq("stun wears off after 1.5 seconds", manager.can_move() and manager.can_attack(), true)
	manager.apply("Silence")
	_eq("silence: cannot cast", manager.can_cast(), false)
	_eq("silence: can still attack", manager.can_attack(), true)
	manager.clear()
	manager.apply("Root")
	_eq("root: cannot move", manager.can_move(), false)
	_eq("root: can still attack", manager.can_attack(), true)

	manager = StatusEffectManager.new()
	_eq("no effects: normal damage", manager.damage_taken_multiplier(), 1.0)
	manager.apply("Shadow Mark")
	_near("shadow mark: +15% damage taken", manager.damage_taken_multiplier(), 1.15)

	manager = StatusEffectManager.new()
	manager.apply("Regeneration")
	var heal_events := manager.update(1.0, 1000.0)
	_eq("regeneration heals", heal_events[0]["kind"], "heal")
	_near("...1% of max health", heal_events[0]["amount"], 10.0)

	manager = StatusEffectManager.new()
	manager.apply("Starfall")
	_eq("starfall ticks once", manager.update(1.0, 1000.0).size(), 1)
	_eq("...and is gone", manager.active_ids().size(), 0)

	manager = StatusEffectManager.new()
	manager.apply("Poison")
	manager.apply("Stun")
	manager.cleanse()
	_eq("cleanse removes everything cleansable", manager.active_ids().size(), 0)


func _test_combatant() -> void:
	print("[combat] --- combatant ---")
	var counters := {"damaged": 0, "died": 0, "healed": 0}
	var fighter := _fighter("Test", {"max_health": 100, "max_mana": 40, "max_stamina": 60, "move_speed": 7.0})
	fighter.damaged.connect(func(_result: Dictionary) -> void: counters["damaged"] += 1)
	fighter.died.connect(func() -> void: counters["died"] += 1)
	fighter.healed.connect(func(_amount: int) -> void: counters["healed"] += 1)

	_eq("starts at full health, mana and stamina", [fighter.hp, fighter.mp, fighter.sp], [100, 40, 60])
	fighter.take_damage(30)
	_eq("damage lowers health", fighter.hp, 70)
	_eq("...and is announced", counters["damaged"], 1)
	fighter.heal(20)
	_eq("healing raises health", fighter.hp, 90)
	fighter.heal(500)
	_eq("healing stops at the maximum", fighter.hp, 100)
	_eq("healing at full health announces nothing new", counters["healed"], 2)
	fighter.take_damage(500)
	_eq("health stops at 0", fighter.hp, 0)
	_eq("it is dead", fighter.is_dead, true)
	_eq("death is announced once", counters["died"], 1)
	fighter.take_damage(50)
	fighter.heal(50)
	_eq("the dead take no damage and cannot be healed", fighter.hp, 0)
	fighter.revive(0.5)
	_eq("revive at half health", fighter.hp, 50)
	_eq("...and alive again", fighter.is_dead, false)

	var dummy := _fighter("Dummy", {"max_health": 1000})
	dummy.immortal = true
	dummy.take_damage(999999)
	_eq("an immortal combatant refills instead of dying", [dummy.is_dead, dummy.hp], [false, 1000])

	fighter = _fighter("Share", {"max_health": 100})
	fighter.take_damage(50)
	fighter.set_base_stats({"max_health": 200})
	_eq("new base stats keep the share of health (50% of 200)", fighter.hp, 100)

	fighter = _fighter("Slowed", {"max_health": 1000, "move_speed": 7.0})
	fighter.status.apply("Slow")
	_near("a status effect changes the stats to fight with", fighter.stats["move_speed"], 4.55)
	_near("...but not the base stats", fighter.base_stats["move_speed"], 7.0)
	fighter.tick(6.0)
	_near("the effect wears off and the stats come back", fighter.stats["move_speed"], 7.0)

	fighter = _fighter("Poisoned", {"max_health": 1000})
	fighter.status.apply("Poison")
	fighter.tick(1.0)
	_eq("poison takes 0.6% of 1000 per second", fighter.hp, 994)
	fighter = _fighter("Marked", {"max_health": 1000})
	fighter.status.apply("Burn")
	fighter.status.apply("Shadow Mark")
	fighter.tick(1.0)
	_eq("burn 10 x 1.15 shadow mark = 11", fighter.hp, 989)
	fighter = _fighter("Healed", {"max_health": 1000})
	fighter.take_damage(500)
	fighter.status.apply("Regeneration")
	fighter.tick(2.0)
	_eq("regeneration heals 1% twice", fighter.hp, 520)
	fighter = _fighter("Killed by poison", {"max_health": 100})
	fighter.hp = 1
	fighter.status.apply("Poison")
	fighter.tick(1.0)
	_eq("damage over time can kill", fighter.is_dead, true)


func _test_resolver() -> void:
	print("[combat] --- resolver ---")
	var attacker := _fighter("Hero", {"max_health": 500, "atk_power": 21, "accuracy": 90.0, "crit_chance": 5.0, "crit_damage": 150.0})
	attacker.attack_profile = {"min": 10, "max": 18}
	var target := _fighter("Target", {"max_health": 100})
	var seen: Array = []
	target.damaged.connect(func(result: Dictionary) -> void: seen.append(result))

	var first := CombatResolver.attack(attacker, target, 1.0, _rolls())
	_eq("attack: ok", first["ok"], true)
	_eq("attack: 35 damage", first["damage"], 35)
	_eq("target health 65", target.hp, 65)
	_eq("the target announced the hit", seen.size(), 1)
	_eq("not a kill yet", first["killed"], false)
	CombatResolver.attack(attacker, target, 1.0, _rolls())
	var third := CombatResolver.attack(attacker, target, 1.0, _rolls())
	_eq("third hit kills", third["killed"], true)
	_eq("target is dead", target.is_dead, true)
	_eq("hitting the dead is refused", CombatResolver.attack(attacker, target, 1.0, _rolls())["error"], "TARGET_DEAD")

	target = _fighter("Target", {"max_health": 100})
	var miss_seen: Array = []
	target.damaged.connect(func(result: Dictionary) -> void: miss_seen.append(result))
	var miss := CombatResolver.attack(attacker, target, 1.0, _rolls({"hit": 99.0}))
	_eq("a miss leaves health alone", target.hp, 100)
	_eq("...but the target still announces it", miss_seen.size(), 1)
	_eq("...as a miss", miss_seen[0]["outcome"], "miss")

	attacker.status.apply("Stun")
	_eq("a stunned fighter cannot attack", CombatResolver.attack(attacker, target, 1.0, _rolls())["error"], "CANNOT_ATTACK")
	attacker.status.clear()

	attacker.attack_profile = {"min": 10, "max": 18, "on_hit": {"effect": "Burn", "chance": 0.5}}
	var burned := CombatResolver.attack(attacker, target, 1.0, _rolls({"status": 10.0}))
	_eq("weapon status applies when the roll is under the chance", burned.get("applied_status", ""), "burn")
	_eq("the target is burning", target.status.has("burn"), true)
	target.status.clear()
	var clean := CombatResolver.attack(attacker, target, 1.0, _rolls({"status": 60.0}))
	_eq("...and does not when it is over", clean.has("applied_status"), false)

	var armored := _fighter("Armored", {"max_health": 1000, "def_power": 100})
	armored.status.apply("Armor Break")
	armored.status.apply("Armor Break")
	armored.status.apply("Armor Break")
	attacker.attack_profile = {"min": 10, "max": 18}
	_eq("armor break makes the same attack hurt more (def 100 -> 70)", CombatResolver.attack(attacker, armored, 1.0, _rolls())["damage"], 20)

	var marked := _fighter("Marked", {"max_health": 1000})
	marked.status.apply("Shadow Mark")
	_eq("shadow mark makes an attack hurt 15% more", CombatResolver.attack(attacker, marked, 1.0, _rolls())["damage"], 40)


func _test_profiles_and_enemy_stats() -> void:
	print("[combat] --- weapons and enemy stats ---")
	var flame := CombatProfile.for_weapon("flame_blade")
	_eq("flame blade damage range", [flame["min"], flame["max"]], [45, 70])
	_eq("flame blade uses attack power", flame["stat"], "atk_power")
	_eq("flame blade element", [flame["element"], flame["element_amount"]], ["Fire", 25.0])
	_eq("flame blade burns", flame["on_hit"]["effect"], "Burn")
	_near("...with a 25% chance", flame["on_hit"]["chance"], 0.25)
	var staff := CombatProfile.for_weapon("archmage_staff")
	_eq("archmage staff uses magic power", staff["stat"], "magic_power")
	_eq("archmage staff element", staff["element"], "Holy")
	_eq("wooden sword has no element and no status", [CombatProfile.for_weapon("wooden_sword").has("element"), CombatProfile.for_weapon("wooden_sword").has("on_hit")], [false, false])
	_eq("armor is not a weapon", CombatProfile.for_weapon("iron_armor"), {})
	_eq("no weapon worn means bare hands", CombatProfile.for_character({"equipment": {}}), {})
	_eq("a worn weapon is found", CombatProfile.for_character({"equipment": {"weapon": {"uid": "x", "item_id": "iron_sword"}}})["min"], ItemDB.weapon_damage("iron_sword")["min"])
	_near("0.25 is read as 25%", CombatProfile.to_fraction(0.25), 0.25)
	_near("36 is read as 36%", CombatProfile.to_fraction(36.0), 0.36)
	_near("100 is read as 100%", CombatProfile.to_fraction(100.0), 1.0)

	var beast := EnemyStats.from_enemy("blackthorn_dreadbeast")
	_eq("Blackthorn max_health is copied as it is", beast["max_health"], 380000.0)
	_eq("Blackthorn attack", beast["atk_power"], 2850.0)
	_eq("Blackthorn defense", beast["def_power"], 1650.0)
	_eq("Blackthorn crit chance and damage", [beast["crit_chance"], beast["crit_damage"]], [14.0, 230.0])
	_eq("Blackthorn block and parry", [beast["block_rate"], beast["parry_rate"]], [18.0, 5.0])
	_eq("the training dummy has no attack", EnemyStats.from_enemy("training_dummy")["atk_power"], 0.0)
	_eq("an unknown enemy gives nothing", EnemyStats.from_enemy("not_an_enemy"), {})
	_eq("the enemy data itself is unchanged", [int(DataRegistry.get_enemy("blackthorn_dreadbeast")["max_health"]), int(DataRegistry.get_enemy("blackthorn_dreadbeast")["crit chance"])], [380000, 14])
	_eq("all 104 enemies are still there", DataRegistry.get_ids("enemies").size(), 104)
