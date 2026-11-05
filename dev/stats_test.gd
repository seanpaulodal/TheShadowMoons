extends Node
## DEV ONLY. Fixed scenarios for StatCalculator and Progression (M3.2 / M3.3).
## Run with F6 and read the Output panel: every line should say PASS.
## The expected numbers match the placeholder data files; if you change the
## data (class stats, rules, EXP curve), update the numbers here as well.

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_test_data()
	_test_stats()
	_test_progression()
	print("[stats] RESULT: %d passed, %d failed" % [_passed, _failed])


# ---------- helpers ----------

func _eq(label: String, got: Variant, expected: Variant) -> void:
	_report(label, got == expected, "expected %s, got %s" % [str(expected), str(got)])


func _near(label: String, got: float, expected: float) -> void:
	_report(label, absf(got - expected) < 0.011, "expected %s, got %s" % [str(expected), str(got)])


func _report(label: String, passed: bool, detail: String) -> void:
	if passed:
		_passed += 1
		print("[stats] PASS  ", label)
	else:
		_failed += 1
		print("[stats] FAIL  %s  (%s)" % [label, detail])


func _stats(class_id: String, level: int, allocated: Dictionary = {}, modifiers: Array = []) -> Dictionary:
	return StatCalculator.calculate(class_id, level, allocated, modifiers)


# ---------- tests ----------

func _test_data() -> void:
	print("[stats] --- data ---")
	var report := DataRegistry.get_report()
	_eq("classes loaded", int(report["counts"].get("classes", 0)), 9)
	_eq("stat_rules loaded", int(report["counts"].get("stat_rules", 0)), 1)
	_eq("progression loaded", int(report["counts"].get("progression", 0)), 1)
	for class_id in Session.CLASS_IDS:
		_report("class data exists: %s" % class_id,
				not DataRegistry.get_class_data(class_id).is_empty(), "missing")


func _test_stats() -> void:
	print("[stats] --- stats ---")
	var warrior := _stats("warrior", 1)
	_eq("warrior L1 ok", warrior["ok"], true)
	_eq("warrior L1 max_health", warrior["stats"]["max_health"], 134)
	_eq("warrior L1 max_mana", warrior["stats"]["max_mana"], 36)
	_eq("warrior L1 atk_power", warrior["stats"]["atk_power"], 21)
	_eq("warrior L1 def_power", warrior["stats"]["def_power"], 12)
	_near("warrior L1 crit_chance", warrior["stats"]["crit_chance"], 5.8)
	_near("warrior L1 block_rate", warrior["stats"]["block_rate"], 5.0)
	_eq("warrior total vit = start 8", warrior["attributes"]["vit"], 8)
	_report("resource stats are whole numbers", warrior["stats"]["max_health"] is int, "not an int")

	var mage := _stats("mage", 1)
	_eq("mage L1 max_mana", mage["stats"]["max_mana"], 116)
	_eq("mage L1 magic_power", mage["stats"]["magic_power"], 26)
	_eq("mage L1 max_health", mage["stats"]["max_health"], 82)

	var archer := _stats("archer", 50)
	_eq("archer L50 max_health (level growth)", archer["stats"]["max_health"], 474)
	_eq("archer L50 atk_power", archer["stats"]["atk_power"], 72)
	_near("archer L50 accuracy", archer["stats"]["accuracy"], 99.5)

	var spent := _stats("mage", 1, {"int": 10})
	_eq("10 points in INT: max_mana", spent["stats"]["max_mana"], 166)
	_eq("10 points in INT: magic_power", spent["stats"]["magic_power"], 46)
	_eq("10 points in INT: total int", spent["attributes"]["int"], 19)

	var sword := [{"stat": "atk_power", "flat": 10.0, "percent": 10.0, "source": "test:sword"}]
	_eq("equipment: flat 10 then +10% on atk_power",
			_stats("warrior", 1, {}, sword)["stats"]["atk_power"], 34)
	_eq("unequipping restores the base value (no leftover bonus)",
			_stats("warrior", 1, {}, [])["stats"]["atk_power"], 21)
	var twice := _stats("warrior", 1, {}, sword)
	var again := _stats("warrior", 1, {}, sword)
	_eq("same input gives the same result every time", twice["stats"], again["stats"])

	_eq("crit_chance is capped at 100",
			_stats("rogue", 1, {}, [{"stat": "crit_chance", "flat": 500.0}])["stats"]["crit_chance"], 100)

	var ignored := _stats("warrior", 1, {}, [{"stat": "nonsense_stat", "flat": 99.0}])
	_eq("unknown stat in a modifier is ignored", ignored["ignored_modifiers"], ["nonsense_stat"])
	_eq("...and changes nothing", ignored["stats"]["atk_power"], 21)

	_eq("level 0 is treated as level 1", _stats("warrior", 0)["stats"], warrior["stats"])
	var capped := _stats("warrior", 999)
	_eq("level 999 is capped to 300", capped["level"], 300)
	_eq("warrior L300 max_health", capped["stats"]["max_health"], 3423)

	var unknown := _stats("wizard", 1)
	_eq("unknown class fails", unknown["ok"], false)
	_eq("...with a clear code", unknown["error"], "UNKNOWN_CLASS")


func _test_progression() -> void:
	print("[stats] --- progression ---")
	_eq("max level", Progression.max_level(), 300)
	_eq("exp to next at level 1", Progression.exp_to_next(1), 100)
	_eq("exp to next at level 10", Progression.exp_to_next(10), 10000)
	_eq("exp to next at level 299", Progression.exp_to_next(299), 8940100)
	_eq("exp to next at level 300 (cap)", Progression.exp_to_next(300), 0)

	var fresh := {"level": 1, "exp": 0, "stat_points": 0, "rebirth": 0}
	var one := Progression.add_exp(fresh, 100)
	_eq("100 exp: level 2", one["state"]["level"], 2)
	_eq("100 exp: no exp left over", one["state"]["exp"], 0)
	_eq("100 exp: 5 stat points", one["state"]["stat_points"], 5)
	_eq("100 exp: 1 level gained", one["levels_gained"], 1)
	_eq("original state is not changed", fresh["level"], 1)

	var partial := Progression.add_exp(fresh, 250)
	_eq("250 exp: level 2", partial["state"]["level"], 2)
	_eq("250 exp: 150 left toward level 3", partial["state"]["exp"], 150)

	var three := Progression.add_exp(fresh, 1400)
	_eq("1400 exp: level 4", three["state"]["level"], 4)
	_eq("1400 exp: 3 levels gained", three["levels_gained"], 3)
	_eq("1400 exp: 15 stat points", three["state"]["stat_points"], 15)

	var huge := Progression.add_exp(fresh, 1000000000000)
	_eq("huge exp stops at level 300", huge["state"]["level"], 300)
	_eq("...exp is cleared at the cap", huge["state"]["exp"], 0)
	_eq("...299 levels gained", huge["levels_gained"], 299)
	_eq("...1495 stat points", huge["state"]["stat_points"], 1495)

	var negative := Progression.add_exp(fresh, -50)
	_eq("negative exp changes nothing", negative["state"]["exp"], 0)

	var with_points := {"level": 5, "exp": 0, "stat_points": 5, "rebirth": 0}
	var spent := Progression.allocate(with_points, {}, "str", 3)
	_eq("allocate 3 into STR: ok", spent["ok"], true)
	_eq("...2 points left", spent["state"]["stat_points"], 2)
	_eq("...STR is 3", spent["allocated"]["str"], 3)
	_eq("...original points untouched", with_points["stat_points"], 5)
	var too_many := Progression.allocate(spent["state"], spent["allocated"], "str", 3)
	_eq("spending more than you have fails", too_many["error"], "NOT_ENOUGH_POINTS")
	_eq("unknown attribute fails", Progression.allocate(with_points, {}, "mana", 1)["error"], "UNKNOWN_ATTRIBUTE")
	_eq("amount 0 fails", Progression.allocate(with_points, {}, "str", 0)["error"], "INVALID_AMOUNT")

	_eq("no rebirth at level 299", Progression.can_rebirth({"level": 299, "rebirth": 0}), false)
	_eq("rebirth possible at level 300", Progression.can_rebirth({"level": 300, "rebirth": 0}), true)
	var reborn := Progression.apply_rebirth({"level": 300, "exp": 0, "stat_points": 7, "rebirth": 0})
	_eq("rebirth resets to level 1", reborn["state"]["level"], 1)
	_eq("rebirth count goes up", reborn["state"]["rebirth"], 1)
	_eq("rebirth keeps unspent points (for now)", reborn["state"]["stat_points"], 7)
	_eq("no rebirth past the maximum (10)", Progression.can_rebirth({"level": 300, "rebirth": 10}), false)
	_eq("rebirth at 299 fails", Progression.apply_rebirth({"level": 299, "rebirth": 0})["error"], "CANNOT_REBIRTH")
