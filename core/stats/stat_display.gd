class_name StatDisplay
extends RefCounted
## How stats, attributes and numbers are written on screen. Names, units,
## groups and the EXP text live here so every screen says the same thing.

const NAMES := {
	"max_health": "Max HP", "max_mana": "Max MP", "max_stamina": "Max SP",
	"atk_power": "Attack", "magic_power": "Magic Power",
	"def_power": "Defense", "magic_resist": "Magic Resist",
	"atk_speed": "Attack Speed", "move_speed": "Move Speed", "attack_range": "Attack Range",
	"accuracy": "Accuracy", "crit_chance": "Crit Chance", "crit_damage": "Crit Damage",
	"evasion": "Evasion", "block_rate": "Block Rate", "block_mitigation": "Block Reduction",
	"parry_rate": "Parry Rate",
}

## Stats that are written with a % sign.
const PERCENT_STATS: Array[String] = [
	"accuracy", "crit_chance", "crit_damage", "evasion", "block_rate", "block_mitigation", "parry_rate",
]

## The stat table is shown in these groups, in this order.
const GROUPS := [
	["Resources", ["max_health", "max_mana", "max_stamina"]],
	["Offense", ["atk_power", "magic_power", "atk_speed", "accuracy", "crit_chance", "crit_damage", "attack_range"]],
	["Defense", ["def_power", "magic_resist", "evasion", "block_rate", "block_mitigation", "parry_rate"]],
	["Movement", ["move_speed"]],
]

const ATTRIBUTE_NAMES := {
	"str": "Strength", "int": "Intelligence", "vit": "Vitality", "dex": "Dexterity",
	"wis": "Wisdom", "lck": "Luck", "agi": "Agility", "cha": "Charisma",
}


static func stat_name(stat: String) -> String:
	return str(NAMES.get(stat, stat.capitalize().replace("_", " ")))


## A stat value as text: 1,234 / 5.8% / 1.03x / 7.06.
static func format_stat(stat: String, value: Variant) -> String:
	var number := float(value)
	if PERCENT_STATS.has(stat):
		return "%s%%" % _plain(number)
	if stat == "atk_speed":
		return "%.2fx" % number
	if stat == "move_speed":
		return "%.2f" % number
	if stat == "attack_range":
		return _plain(number)
	return format_number(int(round(number))) if is_equal_approx(number, round(number)) else "%.2f" % number


## A bonus with a sign: +15 / -5% / +0.25x.
static func format_bonus(stat: String, value: Variant) -> String:
	var number := float(value)
	var sign_text := "+" if number >= 0.0 else "-"
	var magnitude := absf(number)
	if PERCENT_STATS.has(stat):
		return "%s%s%%" % [sign_text, _plain(magnitude)]
	if stat == "atk_speed":
		return "%s%.2fx" % [sign_text, magnitude]
	return "%s%s" % [sign_text, _plain(magnitude)]


## 1234567 -> "1,234,567".
static func format_number(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return ("-" if value < 0 else "") + result


## How far through the current level (0 to 1).
static func exp_fraction(level: int, exp_now: int, rebirth: int = 0) -> float:
	var needed := Progression.exp_to_next(level, rebirth)
	if needed <= 0:
		return 1.0
	return clampf(float(exp_now) / float(needed), 0.0, 1.0)


## "Level 27 (EXP 88.8889%)" - or "Level 300 (MAX)" at the top.
static func exp_text(level: int, exp_now: int, rebirth: int = 0) -> String:
	if Progression.exp_to_next(level, rebirth) <= 0:
		return "Level %d (MAX)" % level
	return "Level %d (EXP %.4f%%)" % [level, exp_fraction(level, exp_now, rebirth) * 100.0]


static func _plain(number: float) -> String:
	return str(int(round(number))) if is_equal_approx(number, round(number)) else "%.1f" % number
