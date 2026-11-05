extends Node
## DEV ONLY. Checks that the Firestore security rules refuse cheating.
## Needs a saved login and a character in slot 1 (use the game or the
## character test screen once). Never ship this folder: exclude "dev/*"
## in the export settings. Read the results in the Output panel.

var _passed: int = 0
var _failed: int = 0
var _now: String = ""


func _ready() -> void:
	await get_tree().process_frame
	_now = Time.get_datetime_string_from_system(true)

	var restore: Dictionary = await FirebaseService.try_restore_session()
	if not restore["ok"]:
		print("[rules] Not signed in. Sign in first (run the game once), then run this again.")
		return
	var loaded: Dictionary = await Session.load_character(1)
	if not loaded["ok"] or not loaded["found"]:
		print("[rules] No character in slot 1. Create one first, then run this again.")
		return

	var path := Session.character_path(1)
	var level := int(Session.character.get("level", 1))
	var existing_name := str(Session.character.get("name", "")).to_lower()
	print("[rules] Testing as uid %s, character '%s'" % [FirebaseService.uid, existing_name])

	print("[rules] --- these must be REFUSED ---")
	_check("create character with level 99",
			await FirestoreService.create_documents([
				_name_entry("rulestest_a", "slot_2"),
				_char_entry("rulestest_a", "slot_2", {"level": 99})]),
			"PERMISSION_DENIED")
	_check("create character with 5000 gold",
			await FirestoreService.create_documents([
				_name_entry("rulestest_b", "slot_2"),
				_char_entry("rulestest_b", "slot_2", {"gold": 5000})]),
			"PERMISSION_DENIED")
	_check("reserve a name with no character (name squatting)",
			await FirestoreService.create_documents([_name_entry("rulestest_c", "slot_3")]),
			"PERMISSION_DENIED")
	_check("create a character in slot 9",
			await FirestoreService.create_documents([
				_name_entry("rulestest_d", "slot_9"),
				_char_entry("rulestest_d", "slot_9", {})]),
			"PERMISSION_DENIED")
	_check("set level to 301",
			await FirestoreService.update_fields(path, {"level": 301, "updated_at": _now}),
			"PERMISSION_DENIED")
	_check("change class",
			await FirestoreService.update_fields(path, {"class_id": "mage", "updated_at": _now}),
			"PERMISSION_DENIED")
	_check("change character name",
			await FirestoreService.update_fields(path, {"name": "Hacker", "updated_at": _now}),
			"PERMISSION_DENIED")
	_check("negative gold",
			await FirestoreService.update_fields(path, {"gold": -5, "updated_at": _now}),
			"PERMISSION_DENIED")
	_check("replace the whole character document",
			await FirestoreService.set_document(path, {"level": 5}),
			"PERMISSION_DENIED")
	_check("read another player's profile",
			await FirestoreService.get_document("tsm_players/someone_else"),
			"PERMISSION_DENIED")
	_check("read a name reservation",
			await FirestoreService.get_document("tsm_names/%s" % existing_name),
			"PERMISSION_DENIED")

	print("[rules] --- name must be unique ---")
	_check("second character with an already-used name",
			await FirestoreService.create_documents([
				_name_entry(existing_name, "slot_2"),
				_char_entry(existing_name, "slot_2", {})]),
			"ALREADY_EXISTS")

	print("[rules] --- this must WORK ---")
	_check("normal save (level unchanged)",
			await FirestoreService.update_fields(path, {"level": level, "updated_at": _now}),
			"OK")

	print("[rules] RESULT: %d passed, %d failed" % [_passed, _failed])


func _name_entry(char_name: String, slot: String) -> Dictionary:
	return {
		"path": "tsm_names/%s" % char_name.to_lower(),
		"data": {"uid": FirebaseService.uid, "name": char_name, "slot": slot, "created_at": _now},
	}


func _char_entry(char_name: String, slot: String, overrides: Dictionary) -> Dictionary:
	var doc := {
		"schema_version": 1, "name": char_name, "class_id": "mage",
		"appearance": {"body": 0, "hair": 0, "face": 0, "skin": 0},
		"level": 1, "exp": 0, "rebirth": 0, "stat_points": 0, "gold": 0,
		"current_map": "map_1", "inventory": [], "equipment": {},
		"created_at": _now, "updated_at": _now,
	}
	doc.merge(overrides, true)
	return {
		"path": "tsm_players/%s/characters/%s" % [FirebaseService.uid, slot],
		"data": doc,
	}


func _check(label: String, result: Dictionary, expected: String) -> void:
	var passed := false
	if expected == "OK":
		passed = result["ok"]
	else:
		passed = (not result["ok"]) and str(result.get("error", "")) == expected
	if passed:
		_passed += 1
		print("[rules] PASS  ", label)
	else:
		_failed += 1
		print("[rules] FAIL  %s  (expected %s, got %s)" % [label, expected,
				"OK" if result["ok"] else str(result.get("error", "?"))])
