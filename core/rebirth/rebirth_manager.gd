class_name RebirthManager
extends RefCounted

## Rebirth System: Character reset with level 1, preserved progress, and 5 points per rebirth.
## Rebirth Rank 1-10 with 50 total points (5 per rebirth).

signal rebirth_achieved(rank: int, points: int)
signal rebirth_failed(reason: String)
signal rebirth_rewards(rank: int, points: int)

var character: Dictionary = {}
var rebirth_points: int = 0
var rebirth_points_allocated: Dictionary = {}
var current_rebirth: int = 0
const MAX_REBIRTH := 10
const MAX_POINTS := 50

func _ready() -> void:
	Session.character_loaded.connect(_sync_character)
	Session.character_changed.connect(_sync_character)

func _sync_character(character: Dictionary) -> void:
	character = character
	if character.is_empty():
		return
	current_rebirth = int(character.get("rebirth", 0))
	rebirth_points = int(character.get("rebirth_points", 0))
	rebirth_points_allocated = character.get("rebirth_points_allocated", {})

func can_rebirth() -> bool:
	if current_rebirth >= MAX_REBIRTH:
		return false
	return int(character.get("level", 1)) >= 300

func perform_rebirth() -> Dictionary:
	if not can_rebirth():
		return {"ok": false, "error": "CANNOT_REBIRTH", "message": "Must be level 300 and under rebirth 10."}

	var updated := character.duplicate(true)
	updated["level"] = 1
	updated["exp"] = 0
	updated["rebirth"] = current_rebirth + 1

	var new_points := rebirth_points + 5
	if new_points > MAX_POINTS:
		new_points = MAX_POINTS
	updated["rebirth_points"] = new_points

	return {
		"ok": true,
		"character": updated,
		"rebirth_rank": current_rebirth + 1,
		"rebirth_points": new_points
	}

func max_rebirth_points() -> int:
	return MAX_POINTS

func max_rebirth_rank() -> int:
	return MAX_REBIRTH

func points_for_rank(rank: int) -> int:
	return mini(rank * 5, MAX_POINTS)

func title_for_rank(rank: int) -> String:
	match rank:
		0: return "Mortal"
		1: return "Awakened"
		2: return "Ascendant"
		3: return "Elite"
		4: return "Exalted"
		5: return "Champion"
		6: return "Veteran"
		7: return "Legendary"
		8: return "Mythic"
		9: return "Celestial"
		10: return "Eternal"
		_: return "Unknown"
