class_name CharacterStats
extends RefCounted
## The one place that answers "what are this character's stats right now?"
##
##   final stats = class + level + allocated attribute points  (the character's own build)
##               + bonuses from every piece of worn equipment  (weapon, armor, helmet,
##                 gloves, pants, boots, rings, accessory, pet, mount)
##
## It only READS the character and the item data. It never touches the enemy
## data, and enemy stats are not part of any of this.
##
## character = a saved character (Session.character): class_id, level,
## attributes {str: n, ...}, equipment {slot: {uid, item_id}}.


## Returns the result of StatCalculator.calculate() plus three extras:
##   "base_stats"       the stats without any equipment
##   "equipment_bonus"  final minus base, per stat (what the gear adds)
##   "modifiers"        the list of equipment bonuses that were used
## `extra_modifiers` is for temporary bonuses (buffs, tests).
## `mounted` decides whether the equipped mount's bonus counts (only while riding).
static func compute(character: Dictionary, mounted: bool = false,
		extra_modifiers: Array = []) -> Dictionary:
	var class_id := str(character.get("class_id", ""))
	var level := int(character.get("level", 1))
	var allocated: Dictionary = character.get("attributes", {})

	var modifiers := Equipment.modifiers(character.get("equipment", {}), mounted)
	modifiers.append_array(extra_modifiers)

	var total := StatCalculator.calculate(class_id, level, allocated, modifiers)
	if not total["ok"]:
		return total
	var bare := StatCalculator.calculate(class_id, level, allocated, [])

	var bonus := {}
	for stat in total["stats"]:
		bonus[stat] = snappedf(float(total["stats"][stat]) - float(bare["stats"][stat]), 0.01)

	total["base_stats"] = bare["stats"]
	total["equipment_bonus"] = bonus
	total["modifiers"] = modifiers
	return total
