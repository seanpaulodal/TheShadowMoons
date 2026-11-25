class_name SkillBook
extends RefCounted
## The character's skills: skill points, learning and ranking up, and the eight
## equipped slots. Pure logic on the character's "skills" record:
##   {"learned": {skill_id: rank}, "slots": {"skill_1": skill_id or "", ... "skill_8": ...},
##    "abilities": {ability_id: rank}, "trials": {"special": bool, "ultimate": bool}}
## Skill points are not stored: points earned (by level) minus points spent (by
## the ranks below), so they can never drift out of step.


static func _rules() -> Dictionary:
	return DataRegistry.get_config("skill_rules")


## A new character's record: the class's first skill, learned and on slot 1.
static func default_record(class_id: String) -> Dictionary:
	var record := {"learned": {}, "slots": {}, "abilities": {}, "trials": {"special": false, "ultimate": false}}
	for slot_name in SkillDB.SLOT_NAMES:
		record["slots"][slot_name] = ""
	var starter := SkillDB.starter_skill(class_id)
	if starter != "":
		record["learned"][starter] = 1
		record["slots"]["skill_1"] = starter
	return record


## Fills in anything missing from a loaded record (older characters) and makes
## sure the starter skill is there. Returns a new record.
static func normalize(raw: Variant, class_id: String) -> Dictionary:
	var record := default_record(class_id)
	if raw is Dictionary:
		for key in ["learned", "abilities", "trials"]:
			if (raw as Dictionary).get(key) is Dictionary:
				for entry in raw[key]:
					record[key][str(entry)] = raw[key][entry] if key == "trials" else int(raw[key][entry])
		if (raw as Dictionary).get("slots") is Dictionary:
			for slot_name in SkillDB.SLOT_NAMES:
				record["slots"][slot_name] = str(raw["slots"].get(slot_name, record["slots"][slot_name]))
	var starter := SkillDB.starter_skill(class_id)
	if starter != "" and int(record["learned"].get(starter, 0)) < 1:
		record["learned"][starter] = 1
	return record


# ---------- points ----------

static func earned_points(level: int) -> int:
	return maxi(0, level) * int(_rules().get("points_per_level", 3))


static func spent_points(record: Dictionary, class_id: String) -> int:
	var total := 0
	var starter := SkillDB.starter_skill(class_id)
	var free_starter := bool(_rules().get("starter_skill_free", true))
	for skill_id in record.get("learned", {}):
		var free := 1 if (free_starter and str(skill_id) == starter) else 0
		total += SkillDB.point_cost(str(skill_id)) * maxi(0, int(record["learned"][skill_id]) - free)
	for ability_id in record.get("abilities", {}):
		total += int(_rules().get("ability_rank_cost", 8)) * maxi(0, int(record["abilities"][ability_id]) - 1)
	return total


static func available_points(character: Dictionary) -> int:
	var class_id := str(character.get("class_id", ""))
	var record := normalize(character.get("skills"), class_id)
	return earned_points(int(character.get("level", 1))) - spent_points(record, class_id)


static func rank_of(record: Dictionary, skill_id: String) -> int:
	return int(record.get("learned", {}).get(skill_id, 0))


# ---------- learning ----------

const MESSAGES := {
	"UNKNOWN": "Unknown skill.",
	"WRONG_CLASS": "That skill belongs to another class.",
	"MAX_RANK": "Already at the highest rank.",
	"NOT_ENOUGH_POINTS": "Not enough skill points.",
	"NOT_UNLOCKED": "That is not unlocked yet.",
	"NOT_LEARNED": "Learn that skill first.",
	"BAD_SLOT": "That is not a skill slot.",
}


## "" when the skill can be learned or ranked up, otherwise a code. For the
## codes with details ("LEVEL_TOO_LOW", "PREREQUISITE") see message_for().
static func learn_error(character: Dictionary, skill_id: String) -> String:
	var class_id := str(character.get("class_id", ""))
	if not SkillDB.exists(skill_id):
		return "UNKNOWN"
	if SkillDB.class_of(skill_id) != class_id:
		return "WRONG_CLASS"
	var record := normalize(character.get("skills"), class_id)
	var rank := rank_of(record, skill_id)
	if rank >= SkillDB.max_rank(skill_id):
		return "MAX_RANK"
	if int(character.get("level", 1)) < SkillDB.unlock_level(skill_id):
		return "LEVEL_TOO_LOW"
	for prerequisite in SkillDB.prerequisites(skill_id):
		if rank_of(record, str(prerequisite)) < 1:
			return "PREREQUISITE"
	if available_points(character) < SkillDB.point_cost(skill_id):
		return "NOT_ENOUGH_POINTS"
	return ""


static func message_for(code: String, skill_id: String = "") -> String:
	match code:
		"LEVEL_TOO_LOW":
			return "Reach level %d to learn this." % SkillDB.unlock_level(skill_id)
		"PREREQUISITE":
			var names: Array = []
			for prerequisite in SkillDB.prerequisites(skill_id):
				names.append(SkillDB.skill_name(str(prerequisite)))
			return "Learn %s first." % ", ".join(names)
		"NOT_ENOUGH_POINTS":
			return "Not enough skill points (need %d)." % SkillDB.point_cost(skill_id) if skill_id != "" else str(MESSAGES[code])
	return str(MESSAGES.get(code, "That did not work."))


## Learns the skill (rank 1) or raises it one rank. Returns
## {"ok": true, "skills": new record, "rank": rank, "cost": points} or a failure.
## A newly learned skill is put on the first free slot.
static func learn(character: Dictionary, skill_id: String) -> Dictionary:
	var code := learn_error(character, skill_id)
	if code != "":
		return {"ok": false, "error": code, "message": message_for(code, skill_id)}
	var class_id := str(character.get("class_id", ""))
	var record := normalize(character.get("skills"), class_id)
	var rank := rank_of(record, skill_id) + 1
	record["learned"][skill_id] = rank
	if rank == 1 and equipped_slot(record, skill_id) == "":
		var free := first_free_slot(record)
		if free != "":
			record["slots"][free] = skill_id
	return {"ok": true, "skills": record, "rank": rank, "cost": SkillDB.point_cost(skill_id)}


# ---------- equipping ----------

static func first_free_slot(record: Dictionary) -> String:
	for slot_name in SkillDB.SLOT_NAMES:
		if str(record.get("slots", {}).get(slot_name, "")) == "":
			return slot_name
	return ""


## The slot a skill is on, or "".
static func equipped_slot(record: Dictionary, skill_id: String) -> String:
	for slot_name in SkillDB.SLOT_NAMES:
		if str(record.get("slots", {}).get(slot_name, "")) == skill_id:
			return slot_name
	return ""


## Puts a learned skill on a slot. If it was on another slot it moves; whatever was
## on the target slot is replaced. Returns {"ok", "skills"} or a failure.
static func equip(character: Dictionary, skill_id: String, slot_name: String) -> Dictionary:
	if not SkillDB.SLOT_NAMES.has(slot_name):
		return {"ok": false, "error": "BAD_SLOT", "message": message_for("BAD_SLOT")}
	var class_id := str(character.get("class_id", ""))
	var record := normalize(character.get("skills"), class_id)
	if rank_of(record, skill_id) < 1:
		return {"ok": false, "error": "NOT_LEARNED", "message": message_for("NOT_LEARNED")}
	var old_slot := equipped_slot(record, skill_id)
	if old_slot != "":
		record["slots"][old_slot] = ""
	record["slots"][slot_name] = skill_id
	return {"ok": true, "skills": record}


static func unequip(character: Dictionary, slot_name: String) -> Dictionary:
	if not SkillDB.SLOT_NAMES.has(slot_name):
		return {"ok": false, "error": "BAD_SLOT", "message": message_for("BAD_SLOT")}
	var record := normalize(character.get("skills"), str(character.get("class_id", "")))
	record["slots"][slot_name] = ""
	return {"ok": true, "skills": record}


## Forgets every skill and gives all the points back (the starter skill stays).
static func reset(character: Dictionary) -> Dictionary:
	var class_id := str(character.get("class_id", ""))
	var fresh := default_record(class_id)
	var old := normalize(character.get("skills"), class_id)
	fresh["trials"] = old["trials"]
	return {"ok": true, "skills": fresh}


# ---------- ultimates and special attacks ----------

## Both are on their own slots automatically once unlocked. Unlocked by level
## (and by the trial, when require_trials is on in TSM_Skill_Rules.json).
static func ability_unlocked(character: Dictionary, ability_id: String) -> bool:
	var data := SkillDB.ability(ability_id)
	if data.is_empty() or str(data.get("ability_class", "")).to_lower() != str(character.get("class_id", "")):
		return false
	if int(character.get("level", 1)) < int(data.get("unlock_level", 1)):
		return false
	if bool(_rules().get("require_trials", false)):
		var record := normalize(character.get("skills"), str(character.get("class_id", "")))
		var kind := "ultimate" if str(data.get("ability_type", "")) == "ultimate" else "special"
		return bool(record["trials"].get(kind, false))
	return true


## 0 while locked; 1 as soon as it unlocks (free); then up by the points spent.
static func ability_rank(character: Dictionary, ability_id: String) -> int:
	if not ability_unlocked(character, ability_id):
		return 0
	var record := normalize(character.get("skills"), str(character.get("class_id", "")))
	return maxi(1, int(record["abilities"].get(ability_id, 1)))


static func ability_error(character: Dictionary, ability_id: String) -> String:
	if SkillDB.ability(ability_id).is_empty():
		return "UNKNOWN"
	if not ability_unlocked(character, ability_id):
		return "NOT_UNLOCKED"
	if ability_rank(character, ability_id) >= int(SkillDB.ability(ability_id).get("rank_max", 1)):
		return "MAX_RANK"
	if available_points(character) < int(_rules().get("ability_rank_cost", 8)):
		return "NOT_ENOUGH_POINTS"
	return ""


static func rank_up_ability(character: Dictionary, ability_id: String) -> Dictionary:
	var code := ability_error(character, ability_id)
	if code != "":
		var message := message_for(code)
		if code == "NOT_ENOUGH_POINTS":
			message = "Not enough skill points (need %d)." % int(_rules().get("ability_rank_cost", 8))
		return {"ok": false, "error": code, "message": message}
	var record := normalize(character.get("skills"), str(character.get("class_id", "")))
	var rank := ability_rank(character, ability_id) + 1
	record["abilities"][ability_id] = rank
	return {"ok": true, "skills": record, "rank": rank}


## Marks a trial as completed (the trials themselves come with quests).
static func complete_trial(character: Dictionary, kind: String) -> Dictionary:
	if kind != "special" and kind != "ultimate":
		return {"ok": false, "error": "UNKNOWN", "message": "Unknown trial."}
	var record := normalize(character.get("skills"), str(character.get("class_id", "")))
	record["trials"][kind] = true
	return {"ok": true, "skills": record}
