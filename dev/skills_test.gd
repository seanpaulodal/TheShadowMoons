extends Node
## DEV ONLY. Checks the skill system's first part: your skill data (162 skills,
## 9 ultimates, 9 special attacks), skill points, learning and ranking up, the
## eight slots, ultimates and specials, saving on the character, and the skill
## window. Needs no login and saves nothing. Run with F6.

var _passed: int = 0
var _failed: int = 0
var _world: Node3D
var _hud: CombatHud


func _ready() -> void:
	await get_tree().process_frame
	Session.save_enabled = false
	_new_character("warrior")

	_test_data()
	_test_ranks_and_text()
	_test_points_and_learning()
	_test_slots()
	_test_abilities()
	_test_normalize_and_reset()
	_test_session()
	await _test_window()

	Session.save_enabled = true
	Session.clear()
	print("[skills] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float, tolerance: float = 0.011) -> void:
	_report(label, absf(got - expected) <= tolerance, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[skills] PASS  ", label)
	else:
		_failed += 1
		print("[skills] FAIL  %s  (%s)" % [label, detail])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_character(class_id: String, level: int = 1) -> void:
	Session.character = {
		"name": "Fighter", "class_id": class_id, "level": level, "exp": 0, "rebirth": 0,
		"stat_points": 0, "gold": 0, "attributes": {}, "inventory": [], "equipment": {},
	}
	Session.slot = 1
	Session._fill_missing_fields()


func _character(class_id: String, level: int) -> Dictionary:
	return {"class_id": class_id, "level": level, "skills": SkillBook.default_record(class_id)}


func _apply(character: Dictionary, result: Dictionary) -> Dictionary:
	if result["ok"]:
		character["skills"] = result["skills"]
	return result


# ---------- the data ----------

func _test_data() -> void:
	print("[skills] --- your skill data ---")
	_eq("162 skills", DataRegistry.get_ids("skills").size(), 162)
	_eq("9 ultimates", DataRegistry.get_ids("ultimates").size(), 9)
	_eq("9 special attacks", DataRegistry.get_ids("specials").size(), 9)
	_eq("27 specialization paths", DataRegistry.get_config("skill_trees")["paths"].size(), 27)
	var report := SkillDB.validate()
	_eq("the data check finds no errors", report["errors"], [])
	for problem in report["errors"]:
		print("[skills] ERROR ", problem)
	_report("...and notes the placeholder descriptions", report["warnings"].any(func(w: String) -> bool: return "placeholder description" in w))

	var classes := ["warrior", "mage", "archer", "rogue", "gunner", "extreme", "brawler", "healer", "necromancer"]
	var all_good := true
	for class_id in classes:
		if SkillDB.skills_for_class(class_id).size() != 18 or SkillDB.paths_for_class(class_id).size() != 3:
			all_good = false
		for path in SkillDB.paths_for_class(class_id):
			if path["skill_ids"].size() != 6:
				all_good = false
		if SkillDB.starter_skill(class_id) == "" or SkillDB.ultimate_for_class(class_id).is_empty() or SkillDB.special_for_class(class_id).is_empty():
			all_good = false
	_eq("every class has 3 paths of 6 skills, a starter skill, an ultimate and a special", all_good, true)
	_eq("the warrior starts with Iron Slash", [SkillDB.starter_skill("warrior"), SkillDB.skill_name("WAR_01_01")], ["WAR_01_01", "Iron Slash"])
	_eq("the class of a skill", SkillDB.class_of("MAG_01_01"), "mage")
	_eq("the first warrior path", SkillDB.paths_for_class("warrior")[0]["path_name"], "Blade Mastery")
	_eq("the necromancer's ultimate", SkillDB.ultimate_for_class("necromancer")["ability_id"], "NEC_ULT_001")
	_eq("the rogue's special attack", SkillDB.special_for_class("rogue")["ability_id"], "ROG_SPC_001")
	_eq("an ultimate is found by id", SkillDB.ability("WAR_ULT_001")["ability_name"], "Kingdom's Last Stand")
	_eq("a special attack is found by id", SkillDB.ability("WAR_SPC_001")["unlock_level"], 100)
	_eq("an unknown skill", SkillDB.exists("NOPE_01_01"), false)
	_eq("prerequisites are read", SkillDB.prerequisites("WAR_01_02"), ["WAR_01_01"])
	_eq("resource names", [SkillDB.resource_label("rage"), SkillDB.resource_label("shadow_energy")], ["Rage", "Shadow Energy"])


func _test_ranks_and_text() -> void:
	print("[skills] --- ranks and the text ---")
	_near("rank 1 is the baseline", SkillDB.damage_multiplier("WAR_01_01", 1), 1.0)
	_near("rank 6 adds 5 x 12%", SkillDB.damage_multiplier("WAR_01_01", 6), 1.6)
	_near("base damage follows the rank (65 x 1.6)", SkillDB.base_damage_at_rank("WAR_01_01", 6), 104.0)
	_near("effect strength grows 8% per rank (rank 3)", SkillDB.effect_multiplier("WAR_01_01", 3), 1.16)
	_near("the cooldown drops 1.5% a rank (rank 10: 9.7 -> 8.39)", SkillDB.cooldown_at_rank("WAR_01_01", 10), 8.39, 0.02)
	_near("the cost stays 8.6 (no growth per rank)", SkillDB.cost_at_rank("WAR_01_01", 10), 8.6)

	var lines: Array = []
	for line in SkillDB.describe("WAR_01_01", 1):
		lines.append(str(line["text"]))
	_eq("the cost line", lines[0], "Cost: 8.6 Rage")
	_eq("the timing line", lines[1], "Cooldown: 9.7 s    Cast: 0.3 s")
	_report("the range line", lines[2].begins_with("Range: 3 m") and "Area: 3.1 m" in lines[2], lines[2])
	_report("the damage line", lines[3].begins_with("Damage: 65 + 0.4 x STR") and "Physical" in lines[3], lines[3])

	var healthy := true
	var effect_lines_ok := true
	for skill_id in DataRegistry.get_ids("skills"):
		for rank in [1, 5, 10]:
			var described := SkillDB.describe(str(skill_id), rank)
			if described.size() < 3:
				healthy = false
			for line in described:
				var text := str(line["text"])
				if "nan" in text.to_lower() or "inf" in text.to_lower() or text == "":
					healthy = false
		var effect_type := str(SkillDB.skill(str(skill_id))["skill_effect"]["effect_type"])
		if effect_type != "direct_damage":
			if not SkillDB.describe(str(skill_id), 1).any(func(l: Dictionary) -> bool: return l["kind"] == "effect"):
				effect_lines_ok = false
	_eq("all 162 skills can be described at ranks 1, 5 and 10", healthy, true)
	_eq("every skill that is not plain damage explains its effect", effect_lines_ok, true)
	var buff_lines: Array = []
	for line in SkillDB.describe(_first_with_effect("buff"), 1):
		buff_lines.append(str(line["text"]))
	_report("a buff names the stat and the time (Attack Power +10.5% for 10 s)", buff_lines.any(func(t: String) -> bool: return "Attack Power +" in t and " s" in t), str(buff_lines))
	var summon_lines: Array = []
	for line in SkillDB.describe(_first_with_effect("summon"), 1):
		summon_lines.append(str(line["text"]))
	_report("a summon names what it calls", summon_lines.any(func(t: String) -> bool: return t.begins_with("Summons ")), str(summon_lines))
	var ability_lines := SkillDB.describe_ability("WAR_SPC_001", 1)
	_report("a special attack shows its cost and damage", str(ability_lines[0]["text"]) == "Cost: 45 Rage" and ability_lines.any(func(l: Dictionary) -> bool: return str(l["text"]).begins_with("Damage: 520")), str(ability_lines))
	_near("ability rank 3 is stronger (520 x 1.2)", float(str(SkillDB.describe_ability("WAR_SPC_001", 3)[2]["text"]).split(" ")[1]), 624.0, 1.0)


func _first_with_effect(effect_type: String) -> String:
	for skill_id in DataRegistry.get_ids("skills"):
		if str(SkillDB.skill(str(skill_id))["skill_effect"]["effect_type"]) == effect_type:
			return str(skill_id)
	return ""


# ---------- points and learning ----------

func _test_points_and_learning() -> void:
	print("[skills] --- points and learning ---")
	var record := SkillBook.default_record("warrior")
	_eq("a new character knows only the starter, on slot 1", [record["learned"], record["slots"]["skill_1"]], [{"WAR_01_01": 1}, "WAR_01_01"])
	_eq("3 points a level: level 10 earns 30", SkillBook.earned_points(10), 30)
	_eq("the starter skill costs nothing", SkillBook.spent_points(record, "warrior"), 0)
	_eq("a level 1 character has 3 points", SkillBook.available_points(_character("warrior", 1)), 3)

	var hero := _character("warrior", 1)
	var early := SkillBook.learn(hero, "WAR_01_02")
	_eq("a level 15 skill is refused at level 1", early["error"], "LEVEL_TOO_LOW")
	_eq("...with the level in the message", early["message"], "Reach level 15 to learn this.")

	hero = _character("warrior", 300)
	var skipped := SkillBook.learn(hero, "WAR_01_03")
	_eq("a skill needs the one before it", skipped["error"], "PREREQUISITE")
	_eq("...and says which", skipped["message"], "Learn Shadow Cleave first.")
	_eq("a mage can't learn a warrior skill", SkillBook.learn(_character("mage", 300), "WAR_01_02")["error"], "WRONG_CLASS")
	_eq("an unknown skill", SkillBook.learn(hero, "NOPE")["error"], "UNKNOWN")

	hero = _character("warrior", 15)             # 45 points
	var learned := _apply(hero, SkillBook.learn(hero, "WAR_01_02"))
	_eq("a level 15 warrior learns Shadow Cleave", [learned["ok"], learned["rank"], learned["cost"]], [true, 1, 3])
	_eq("...it goes on the first free slot (2)", hero["skills"]["slots"]["skill_2"], "WAR_01_02")
	_eq("...and costs 3 points", SkillBook.available_points(hero), 42)
	var ranked := _apply(hero, SkillBook.learn(hero, "WAR_01_02"))
	_eq("learning it again raises it to rank 2", ranked["rank"], 2)
	_eq("...for 3 more points", SkillBook.available_points(hero), 39)
	var starter_rank := _apply(hero, SkillBook.learn(hero, "WAR_01_01"))
	_eq("the starter's rank 2 costs 2 (rank 1 was free)", [starter_rank["rank"], SkillBook.available_points(hero)], [2, 37])

	# Save up to the limit.
	var poor := _character("warrior", 15)
	poor["skills"]["learned"]["WAR_01_02"] = 5          # 5 ranks x 3 = 15, plus ...
	poor["skills"]["learned"]["WAR_01_01"] = 10         # starter: 9 paid ranks x 2 = 18 -> 33 spent, 12 left
	_eq("with 12 points left", SkillBook.available_points(poor), 12)
	poor["skills"]["learned"]["WAR_01_02"] = 9          # 27 + 18 = 45 spent, 0 left
	_eq("with none left", SkillBook.available_points(poor), 0)
	_eq("a skill is refused when there are not enough points", SkillBook.learn(poor, "WAR_01_02")["error"], "NOT_ENOUGH_POINTS")
	_eq("...and the message says how many", SkillBook.learn(poor, "WAR_01_02")["message"], "Not enough skill points (need 3).")
	var maxed := _character("warrior", 300)
	maxed["skills"]["learned"]["WAR_01_01"] = 10
	_eq("the top rank is 10", SkillBook.learn(maxed, "WAR_01_01")["error"], "MAX_RANK")

	var total := 0
	for skill_id in SkillDB.skills_for_class("warrior"):
		total += SkillDB.point_cost(str(skill_id))
	_eq("learning every skill once costs 81 points (the starter is free: 79)", total - SkillDB.point_cost("WAR_01_01"), 79)
	_eq("a level 300 character has 900 points", SkillBook.available_points(_character("warrior", 300)), 900)

	# Each class can learn its whole first path in order.
	var follow := _character("mage", 300)
	var path_ok := true
	for skill_id in SkillDB.paths_for_class("mage")[0]["skill_ids"]:
		if str(skill_id) == SkillDB.starter_skill("mage"):
			continue
		if not _apply(follow, SkillBook.learn(follow, str(skill_id)))["ok"]:
			path_ok = false
	_eq("a mage can learn a whole path in order", path_ok, true)


# ---------- slots ----------

func _test_slots() -> void:
	print("[skills] --- the eight slots ---")
	var hero := _character("warrior", 300)
	for skill_id in ["WAR_01_02", "WAR_01_03"]:
		_apply(hero, SkillBook.learn(hero, skill_id))
	_eq("learned skills fill slots 2 and 3", [hero["skills"]["slots"]["skill_2"], hero["skills"]["slots"]["skill_3"]], ["WAR_01_02", "WAR_01_03"])
	_eq("the first free slot is 4", SkillBook.first_free_slot(hero["skills"]), "skill_4")
	var moved := _apply(hero, SkillBook.equip(hero, "WAR_01_02", "skill_6"))
	_eq("a skill can move to another slot", moved["ok"], true)
	_eq("...it left its old slot", hero["skills"]["slots"]["skill_2"], "")
	_eq("...and is on the new one", hero["skills"]["slots"]["skill_6"], "WAR_01_02")
	_apply(hero, SkillBook.equip(hero, "WAR_01_03", "skill_6"))
	_eq("putting another skill there replaces it", [hero["skills"]["slots"]["skill_6"], hero["skills"]["slots"]["skill_3"]], ["WAR_01_03", ""])
	_eq("an unlearned skill can't be equipped", SkillBook.equip(hero, "WAR_01_05", "skill_4")["error"], "NOT_LEARNED")
	_eq("slot 9 does not exist", SkillBook.equip(hero, "WAR_01_02", "skill_9")["error"], "BAD_SLOT")
	_eq("slots can be emptied", _apply(hero, SkillBook.unequip(hero, "skill_6"))["ok"] and hero["skills"]["slots"]["skill_6"] == "", true)
	_eq("equipped_slot finds a skill", SkillBook.equipped_slot(hero["skills"], "WAR_01_01"), "skill_1")

	var full := _character("warrior", 300)
	for slot_name in SkillDB.SLOT_NAMES:
		full["skills"]["slots"][slot_name] = "WAR_01_01"
	full["skills"]["slots"]["skill_1"] = "WAR_01_01"
	_apply(full, SkillBook.learn(full, "WAR_01_02"))
	_eq("with every slot full a new skill is learned but not equipped", SkillBook.equipped_slot(full["skills"], "WAR_01_02"), "")


# ---------- ultimates and special attacks ----------

func _test_abilities() -> void:
	print("[skills] --- ultimates and special attacks ---")
	var hero := _character("warrior", 99)
	_eq("the special attack unlocks at level 100: locked at 99", SkillBook.ability_unlocked(hero, "WAR_SPC_001"), false)
	_eq("...rank 0 while locked", SkillBook.ability_rank(hero, "WAR_SPC_001"), 0)
	hero["level"] = 100
	_eq("unlocked at 100", SkillBook.ability_unlocked(hero, "WAR_SPC_001"), true)
	_eq("...at rank 1, free", SkillBook.ability_rank(hero, "WAR_SPC_001"), 1)
	_eq("the ultimate is still locked (level 200)", SkillBook.ability_unlocked(hero, "WAR_ULT_001"), false)
	_eq("another class's ability is never unlocked", SkillBook.ability_unlocked(hero, "MAG_SPC_001"), false)
	var ranked := _apply(hero, SkillBook.rank_up_ability(hero, "WAR_SPC_001"))
	_eq("ranking up gives rank 2", ranked["rank"], 2)
	_eq("...for 8 points", SkillBook.spent_points(hero["skills"], "warrior"), 8)
	for i in 3:
		_apply(hero, SkillBook.rank_up_ability(hero, "WAR_SPC_001"))
	_eq("the top rank is 5", SkillBook.ability_rank(hero, "WAR_SPC_001"), 5)
	_eq("...no further", SkillBook.rank_up_ability(hero, "WAR_SPC_001")["error"], "MAX_RANK")
	_eq("a locked ability can't be ranked up", SkillBook.rank_up_ability(hero, "WAR_ULT_001")["error"], "NOT_UNLOCKED")

	var broke := _character("warrior", 100)
	broke["skills"]["learned"]["WAR_01_01"] = 10
	broke["skills"]["learned"]["WAR_01_02"] = 10
	for skill_id in SkillDB.skills_for_class("warrior"):
		broke["skills"]["learned"][skill_id] = 10
	_eq("without points it is refused", SkillBook.rank_up_ability(broke, "WAR_SPC_001")["error"], "NOT_ENOUGH_POINTS")

	# Trials: off by default, can be switched on in the rules.
	var rules: Dictionary = DataRegistry.get_config("skill_rules")
	rules["require_trials"] = true
	var trial_hero := _character("warrior", 250)
	_eq("with trials required the special stays locked", SkillBook.ability_unlocked(trial_hero, "WAR_SPC_001"), false)
	_apply(trial_hero, SkillBook.complete_trial(trial_hero, "special"))
	_eq("...until its trial is done", SkillBook.ability_unlocked(trial_hero, "WAR_SPC_001"), true)
	_eq("...and the ultimate's trial is separate", SkillBook.ability_unlocked(trial_hero, "WAR_ULT_001"), false)
	rules["require_trials"] = false
	_eq("an unknown trial", SkillBook.complete_trial(trial_hero, "nope")["error"], "UNKNOWN")


func _test_normalize_and_reset() -> void:
	print("[skills] --- old characters and reset ---")
	var fresh := SkillBook.normalize(null, "mage")
	_eq("a character with no skills record gets the starter", fresh["learned"], {"MAG_01_01": 1})
	var damaged := SkillBook.normalize({"learned": {}, "slots": {}}, "mage")
	_eq("a record missing its starter gets it back", damaged["learned"], {"MAG_01_01": 1})
	_eq("missing slots are filled in", damaged["slots"].size(), 8)
	var partial := SkillBook.normalize({"learned": {"MAG_01_01": 3}, "slots": {"skill_2": "MAG_01_01"}, "trials": {"special": true}}, "mage")
	_eq("what was saved is kept", [partial["learned"]["MAG_01_01"], partial["slots"]["skill_2"], partial["trials"]["special"]], [3, "MAG_01_01", true])

	var hero := _character("warrior", 100)
	_apply(hero, SkillBook.learn(hero, "WAR_01_02"))
	_apply(hero, SkillBook.rank_up_ability(hero, "WAR_SPC_001"))
	_apply(hero, SkillBook.complete_trial(hero, "special"))
	var before := SkillBook.available_points(hero)
	_apply(hero, SkillBook.reset(hero))
	_eq("reset forgets everything but the starter", hero["skills"]["learned"], {"WAR_01_01": 1})
	_eq("...gives the points back (300)", SkillBook.available_points(hero), 300)
	_report("...more than before", SkillBook.available_points(hero) > before)
	_eq("...and keeps the trials", hero["skills"]["trials"]["special"], true)
	_eq("...the ability ranks are cleared", hero["skills"]["abilities"], {})


# ---------- the Session ----------

func _test_session() -> void:
	print("[skills] --- saved on the character ---")
	_new_character("warrior")
	_eq("a new character has a skills record", Session.character["skills"]["learned"], {"WAR_01_01": 1})
	_eq("...and 3 points", Session.skill_points(), 3)
	_eq("a level 15 skill is refused at level 1", Session.learn_skill("WAR_01_02")["error"], "LEVEL_TOO_LOW")
	_eq("the starter can be ranked up with the points", Session.learn_skill("WAR_01_01")["ok"], true)
	_eq("...rank 2 (cost 2, one point left)", [Session.character["skills"]["learned"]["WAR_01_01"], Session.skill_points()], [2, 1])
	_eq("...and it is waiting to be saved", Session.has_unsaved_changes(), true)
	_eq("the one point left is not enough", Session.learn_skill("WAR_01_01")["error"], "NOT_ENOUGH_POINTS")

	Session.character["exp"] = 0
	Session.grant_exp(500)
	_report("levelling up gives more points (3 per level)", Session.skill_points() == 1 + 3 * (int(Session.character["level"]) - 1), "level %d, points %d" % [int(Session.character["level"]), Session.skill_points()])
	_eq("equipping through the Session", Session.equip_skill("WAR_01_01", "skill_4")["ok"], true)
	_eq("...it is on slot 4", Session.character["skills"]["slots"]["skill_4"], "WAR_01_01")
	_eq("...and left slot 1", Session.character["skills"]["slots"]["skill_1"], "")
	_eq("unequipping", Session.unequip_skill("skill_4")["ok"], true)
	var rules: Dictionary = DataRegistry.get_config("skill_rules")
	rules["respec_gold"] = 10
	_eq("a reset can cost gold (when set in the rules)", Session.reset_skills()["error"], "NOT_ENOUGH_GOLD")
	Session.character["gold"] = 1000
	var gold_before: int = Session.character["gold"]
	_eq("...and takes it", [Session.reset_skills()["ok"], Session.character["gold"] < gold_before], [true, true])
	rules["respec_gold"] = 0
	_eq("reset is free by default", Session.reset_skills()["ok"], true)
	_eq("...everything is back to the start", Session.character["skills"]["learned"], {"WAR_01_01": 1})
	_new_character("necromancer")
	_eq("a necromancer starts with its own first skill", Session.character["skills"]["learned"].keys(), ["NEC_01_01"])


# ---------- the window ----------

func _test_window() -> void:
	print("[skills] --- the skill window ---")
	_new_character("warrior", 20)
	_world = load("res://maps/world_test.tscn").instantiate()
	add_child(_world)
	await _frames(3)
	_hud = _world.combat_hud
	_world.clear_decor()
	for camp in _world.camps:
		camp.queue_free()
	await _frames(3)

	var buttons := _hud.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text in ["Bag", "Char", "Skills", "Map"])
	_eq("four menu buttons: Bag, Char, Skills, Map", buttons.size(), 4)

	var window := _hud.skill_window
	_hud.open_skills()
	await _frames(2)
	_eq("the Skills button opens the window", window.visible, true)
	_eq("...and switches the touch controls off", _world.controls.enabled, false)
	_report("the header names the class and level", "Warrior" in window._class_label.text and "Level 20" in window._class_label.text, window._class_label.text)
	_eq("the points are shown (3 x 20)", window._points_label.text, "Skill points: 60")
	_eq("the tabs are the three paths and the Ultimate", [(window._tab_buttons[0] as Button).text, (window._tab_buttons[1] as Button).text, (window._tab_buttons[2] as Button).text, (window._tab_buttons[3] as Button).text], ["Blade Mastery", "Iron Fortress", "Berserkers Wrath", "Ultimate"])
	_eq("a path lists its six skills", window._list.get_child_count(), 6)
	_report("the starter shows its rank", (window._list.get_child(0) as Button).text.contains("Rank 1 / 10"), (window._list.get_child(0) as Button).text)
	_report("a skill that can be learned says so", (window._list.get_child(1) as Button).text.contains("Ready to learn"), (window._list.get_child(1) as Button).text)
	_report("a locked skill shows its level", (window._list.get_child(2) as Button).text.contains("Level 35"), (window._list.get_child(2) as Button).text)
	_eq("slot 1 shows the starter's initials", (window._slot_buttons["skill_1"] as Button).text, "1\nIS")
	_eq("an empty slot shows a dash", (window._slot_buttons["skill_2"] as Button).text, "2\n-")

	window.select_skill("WAR_01_02")
	_eq("selecting a skill offers Learn", window._main_button.text, "Learn  (3 points)")
	_eq("...enabled", window._main_button.disabled, false)
	window._on_main()
	await _frames(2)
	_eq("Learn learns it", Session.character["skills"]["learned"].get("WAR_01_02", 0), 1)
	_eq("...says so", window._message.text, "Learned Shadow Cleave (rank 1).")
	_eq("...the points went down", window._points_label.text, "Skill points: 57")
	_eq("...it is on slot 2", (window._slot_buttons["skill_2"] as Button).text, "2\nSC")
	_eq("...and the button now says Rank up", window._main_button.text, "Rank up  (3 points)")
	window._on_main()
	_eq("Rank up raises it", Session.character["skills"]["learned"]["WAR_01_02"], 2)

	window.select_skill("WAR_01_03")
	_eq("a locked skill has a disabled button", window._main_button.disabled, true)
	_report("...and shows why", window._details.get_children().any(func(n: Node) -> bool: return n is Label and "level 35" in (n as Label).text))

	window.select_skill("WAR_01_02")
	window._on_slot("skill_5")
	_eq("tapping a slot moves the selected skill there", [Session.character["skills"]["slots"]["skill_5"], Session.character["skills"]["slots"]["skill_2"]], ["WAR_01_02", ""])
	window._on_slot("skill_5")
	_eq("tapping it again removes it", Session.character["skills"]["slots"]["skill_5"], "")
	window.select_skill("")
	window._on_slot("skill_1")
	_eq("tapping a filled slot selects that skill", window._selected_skill, "WAR_01_01")

	window.show_tab(3)
	_eq("the Ultimate tab lists the special attack and the ultimate", window._list.get_child_count(), 2)
	_report("both are locked at level 20", (window._list.get_child(0) as Button).text.contains("Level 100") and (window._list.get_child(1) as Button).text.contains("Level 200"), (window._list.get_child(0) as Button).text)
	window.select_ability("WAR_SPC_001")
	_eq("a locked ability can't be ranked up", window._main_button.visible, false)
	Session.character["level"] = 100
	Session.character_changed.emit()
	await _frames(2)
	_report("at level 100 the special attack is rank 1", (window._list.get_child(0) as Button).text.contains("Rank 1 / 5"), (window._list.get_child(0) as Button).text)
	_eq("...and can be ranked up", window._main_button.visible and not window._main_button.disabled, true)
	window._on_main()
	_eq("ranking it up costs 8 points", Session.character["skills"]["abilities"]["WAR_SPC_001"], 2)

	window._on_reset()
	await _frames(2)
	_eq("Reset gives everything back", [Session.character["skills"]["learned"], window._points_label.text], [{"WAR_01_01": 1}, "Skill points: 300"])
	_hud.open_inventory()
	_eq("opening another window closes the skills", [window.visible, _hud.inventory_window.visible], [false, true])
	_hud.close_windows()
	_eq("the controls come back", _world.controls.enabled, true)
