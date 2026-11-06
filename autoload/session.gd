extends Node
## Session (autoload): who is playing right now (account profile + active character).
## Cloud layout (Firestore):
##   tsm_players/{uid}                       -> account profile
##   tsm_players/{uid}/characters/slot_{n}   -> one character per slot

signal character_loaded(character: Dictionary)
## Fires whenever the active character changes (items, equipment, attribute
## points, level). Stats and screens listen to this to refresh themselves.
signal character_changed

const SCHEMA_VERSION := 1
const MAX_SLOTS := 4

# The nine classes from the design document. These move into a data file later.
const CLASS_IDS := [
	"warrior", "mage", "archer", "rogue", "gunner",
	"extreme", "brawler", "healer", "necromancer",
]
const NAME_PATTERN := "^[A-Za-z0-9_]{3,16}$"    # must match docs/firestore.rules
const NAME_MIN_LENGTH := 3
const NAME_MAX_LENGTH := 16

var character: Dictionary = {}
var slot: int = 0
## Tests can turn this off to change the character without touching the cloud.
var save_enabled: bool = true

var _saving: bool = false


func _ready() -> void:
	FirebaseService.signed_out.connect(clear)


func has_character() -> bool:
	return not character.is_empty() and slot > 0


func clear() -> void:
	character = {}
	slot = 0


func profile_path() -> String:
	return "tsm_players/%s" % FirebaseService.uid


func character_path(slot_number: int) -> String:
	return "tsm_players/%s/characters/slot_%d" % [FirebaseService.uid, slot_number]


## Checks a character name. Returns "" when it is fine, otherwise a message
## that tells the player exactly what is wrong. Allowed: A-Z, a-z, 0-9 and _.
func name_problem(char_name: String) -> String:
	if char_name == "":
		return "Enter a name."

	var has_space := false
	var bad: PackedStringArray = []
	for i in char_name.length():
		var code := char_name.unicode_at(i)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) or code == 95
		if allowed:
			continue
		var ch := char_name[i]
		if ch == " ":
			has_space = true
		elif not bad.has(ch):
			bad.append(ch)

	var shown := " ".join(bad.slice(0, 5))
	if has_space and not bad.is_empty():
		return "Spaces and special characters (%s) are not allowed. Use only letters, numbers and underscores (_)." % shown
	if has_space:
		return "Spaces are not allowed in names. Use an underscore (_) instead."
	if not bad.is_empty():
		return "Special characters (%s) are not allowed. Use only letters, numbers and underscores (_)." % shown
	if char_name.length() < NAME_MIN_LENGTH:
		return "Name must be at least %d characters." % NAME_MIN_LENGTH
	if char_name.length() > NAME_MAX_LENGTH:
		return "Name can be at most %d characters (you typed %d)." % [NAME_MAX_LENGTH, char_name.length()]
	return ""


## Makes sure the account profile document exists.
func ensure_profile() -> Dictionary:
	if not FirebaseService.is_signed_in():
		return _fail("NOT_SIGNED_IN", "Please sign in first.")

	var existing: Dictionary = await FirestoreService.get_document(profile_path())
	if not existing["ok"]:
		return existing
	if existing["found"]:
		return {"ok": true, "created": false}

	var created: Dictionary = await FirestoreService.set_document(profile_path(), {
		"schema_version": SCHEMA_VERSION,
		"email": FirebaseService.user_email,
		"created_at": Time.get_datetime_string_from_system(true),
	})
	if not created["ok"]:
		return created
	return {"ok": true, "created": true}


## Loads a character into Session.character. Result has "found": true/false.
func load_character(slot_number: int = 1) -> Dictionary:
	if not FirebaseService.is_signed_in():
		return _fail("NOT_SIGNED_IN", "Please sign in first.")

	var result: Dictionary = await FirestoreService.get_document(character_path(slot_number))
	if not result["ok"]:
		return result
	if not result["found"]:
		clear()
		return {"ok": true, "found": false}

	character = result["data"]
	_fill_missing_fields()
	slot = slot_number
	character_loaded.emit(character)
	character_changed.emit()
	return {"ok": true, "found": true}


## Creates a new character in an empty slot and makes it the active one.
func create_character(slot_number: int, char_name: String, class_id: String,
		appearance: Dictionary) -> Dictionary:
	if not FirebaseService.is_signed_in():
		return _fail("NOT_SIGNED_IN", "Please sign in first.")

	var problem := name_problem(char_name)
	if problem != "":
		return _fail("INVALID_NAME", problem)
	if not CLASS_IDS.has(class_id):
		return _fail("INVALID_CLASS", "Unknown class: %s" % class_id)
	if slot_number < 1 or slot_number > MAX_SLOTS:
		return _fail("INVALID_SLOT", "Invalid character slot.")

	var existing: Dictionary = await FirestoreService.get_document(character_path(slot_number))
	if not existing["ok"]:
		return existing
	if existing["found"]:
		return _fail("SLOT_TAKEN", "That slot already has a character.")

	var now := Time.get_datetime_string_from_system(true)
	# Starting values are placeholders. M3 (stats) defines the real ones.
	var doc := {
		"schema_version": SCHEMA_VERSION,
		"name": char_name,
		"class_id": class_id,
		"appearance": appearance,
		"level": 1,
		"exp": 0,
		"rebirth": 0,
		"stat_points": 0,
		"gold": 0,
		"current_map": "map_1",
		"inventory": [],
		"equipment": {},
		"created_at": now,
		"updated_at": now,
	}
	# The name reservation and the character are written together, all or
	# nothing, so two players can never end up with the same name.
	var saved: Dictionary = await FirestoreService.create_documents([
		{
			"path": "tsm_names/%s" % char_name.to_lower(),
			"data": {
				"uid": FirebaseService.uid,
				"name": char_name,
				"slot": "slot_%d" % slot_number,
				"created_at": now,
			},
		},
		{"path": character_path(slot_number), "data": doc},
	])
	if not saved["ok"]:
		if saved["error"] == "ALREADY_EXISTS":
			return _fail("NAME_TAKEN", "That character name is already taken.")
		return saved

	character = doc
	_fill_missing_fields()
	slot = slot_number
	character_loaded.emit(character)
	character_changed.emit()
	return {"ok": true}


## Saves only the listed top-level fields of the active character.
func save_fields(fields: Dictionary) -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")

	var payload := fields.duplicate(true)
	payload["updated_at"] = Time.get_datetime_string_from_system(true)
	var result: Dictionary = await FirestoreService.update_fields(character_path(slot), payload)
	if result["ok"]:
		character.merge(payload, true)
	return result


# ---------- stats and build ----------

## The character's total stats: class + level + allocated points + worn equipment.
func total_stats(mounted: bool = false) -> Dictionary:
	return CharacterStats.compute(character, mounted)


## Spends stat points on one attribute and saves it.
func allocate_attribute(attribute: String, amount: int = 1) -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")
	var outcome := Progression.allocate(_progress_state(), character["attributes"], attribute, amount)
	if not outcome["ok"]:
		return outcome
	return await _commit({
		"attributes": outcome["allocated"],
		"stat_points": outcome["state"]["stat_points"],
	})


## Adds EXP (levels up if it can) and saves it. Result has "levels_gained".
func grant_exp(amount: int) -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")
	var outcome := Progression.add_exp(_progress_state(), amount)
	var state: Dictionary = outcome["state"]
	var result := await _commit({
		"level": state["level"],
		"exp": state["exp"],
		"stat_points": state["stat_points"],
	})
	if result["ok"]:
		result["levels_gained"] = outcome["levels_gained"]
	return result


func add_item(item_id: String, qty: int = 1) -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")
	var outcome := Inventory.add(character["inventory"], item_id, qty)
	if not outcome["ok"]:
		return outcome
	return await _commit({"inventory": outcome["inventory"]})


func remove_item(item_id: String, qty: int = 1) -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")
	var outcome := Inventory.remove(character["inventory"], item_id, qty)
	if not outcome["ok"]:
		return outcome
	return await _commit({"inventory": outcome["inventory"]})


## Wears a piece of gear from the bag (the one with this uid).
func equip_item(uid: String, target_slot: String = "") -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")
	var outcome := Equipment.equip(character["inventory"], character["equipment"], uid,
			{"level": character.get("level", 1), "class_id": character.get("class_id", "")}, target_slot)
	if not outcome["ok"]:
		return outcome
	return await _commit({"inventory": outcome["inventory"], "equipment": outcome["equipped"]})


## Takes the piece in this slot off and puts it back in the bag.
func unequip_item(equipment_slot: String) -> Dictionary:
	if not has_character():
		return _fail("NO_CHARACTER", "No character is loaded.")
	var outcome := Equipment.unequip(character["inventory"], character["equipment"], equipment_slot)
	if not outcome["ok"]:
		return outcome
	return await _commit({"inventory": outcome["inventory"], "equipment": outcome["equipped"]})


## Saves the change, and only then applies it to the local character. If the save
## fails, nothing changes, so the screen never shows something that was not saved.
func _commit(fields: Dictionary) -> Dictionary:
	if _saving:
		return _fail("BUSY", "Still saving the last change.")
	_saving = true
	var result: Dictionary
	if save_enabled:
		result = await save_fields(fields)
	else:
		character.merge(fields.duplicate(true), true)
		result = {"ok": true}
	_saving = false
	if result["ok"]:
		character_changed.emit()
	return result


func _progress_state() -> Dictionary:
	return {
		"level": int(character.get("level", 1)),
		"exp": int(character.get("exp", 0)),
		"stat_points": int(character.get("stat_points", 0)),
		"rebirth": int(character.get("rebirth", 0)),
	}


## Older characters were saved before some fields existed. Fill them in.
func _fill_missing_fields() -> void:
	var attributes: Dictionary = character.get("attributes", {})
	for attribute in StatCalculator.ATTRIBUTES:
		attributes[attribute] = int(attributes.get(attribute, 0))
	character["attributes"] = attributes
	if not (character.get("inventory") is Array):
		character["inventory"] = []
	if not (character.get("equipment") is Dictionary):
		character["equipment"] = {}
	for key in ["exp", "rebirth", "stat_points", "gold"]:
		character[key] = int(character.get(key, 0))


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
