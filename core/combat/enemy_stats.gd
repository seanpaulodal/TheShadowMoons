class_name EnemyStats
extends RefCounted
## Turns an enemy row (TSM_Enemy_Data) into the stat names combat uses.
## It only READS the enemy data. Nothing here changes an enemy's numbers:
## the values are copied as they are in the sheet.


static func from_enemy(enemy_id: String) -> Dictionary:
	var row := DataRegistry.get_enemy(enemy_id)
	return {} if row.is_empty() else from_row(row)


static func from_row(row: Dictionary) -> Dictionary:
	var defense := _number(row.get("def_power"))
	return {
		"max_health": _number(row.get("max_health")),
		"max_mana": _number(row.get("max_mana")),
		"max_stamina": _number(row.get("max_stamina")),
		"atk_power": _number(row.get("atk_power")),
		"magic_power": _number(row.get("atk_power")),
		"def_power": defense,
		"magic_resist": defense,     # the sheet has one defense number
		"atk_speed": _number(row.get("atk_speed")),
		"move_speed": _number(row.get("move_speed")),
		"accuracy": _number(row.get("accuracy")),
		"crit_chance": _number(row.get("crit chance")),
		"crit_damage": _number(row.get("crit DMG")),
		"evasion": _number(row.get("evasion")),
		"block_rate": _number(row.get("block rate")),
		"block_mitigation": _number(row.get("block mitigation")),
		"parry_rate": _number(row.get("parry rate")),
	}


static func _number(value: Variant) -> float:
	return ItemDB._number(value, 0.0)
