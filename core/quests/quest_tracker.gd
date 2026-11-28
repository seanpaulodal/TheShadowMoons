class_name QuestTracker
extends RefCounted
## Quest progress logic. Pure functions over a character dictionary, in the same
## style as Progression / SkillBook: they return new state, Session commits it.
## Quest definitions live in data/TSM_Quests.json and are read by DataRegistry.

## The quest table (id -> quest row).  Empty until TSM_Quests.json has entries.
static func all() -> Dictionary:
	return DataRegistry.get_config("quests")


static func get_quest(quest_id: String) -> Dictionary:
	return all().get(quest_id, {})


## quests the character is allowed to see now (level gate, not already done).
static func available(character: Dictionary) -> Array:
	var level := int(character.get("level", 1))
	var active: Dictionary = character.get("active_quests", {})
	var done: Array = character.get("completed_quests", [])
	var out: Array = []
	for quest_id in all():
		var quest: Dictionary = all()[quest_id]
		if done.has(quest_id) or active.has(quest_id):
			continue
		if int(quest.get("min_level", 1)) > level:
			continue
		out.append(quest_id)
	return out


## {"ok": true, "active_quests": {...}} or {"ok": false, "error", "message"}.
static func accept(character: Dictionary, quest_id: String) -> Dictionary:
	var quest := get_quest(quest_id)
	if quest.is_empty():
		return _fail("UNKNOWN_QUEST", "That quest does not exist.")
	var active: Dictionary = character.get("active_quests", {}).duplicate(true)
	var done: Array = character.get("completed_quests", [])
	if done.has(quest_id):
		return _fail("ALREADY_DONE", "You have already finished that quest.")
	if active.has(quest_id):
		return {"ok": true, "already": true, "active_quests": active}
	active[quest_id] = {"progress": 0}
	return {"ok": true, "already": false, "active_quests": active}


## Adds progress. Returns the new state and whether it completed just now.
static func progress(character: Dictionary, quest_id: String, amount: int = 1) -> Dictionary:
	var active: Dictionary = character.get("active_quests", {}).duplicate(true)
	if not active.has(quest_id):
		return _fail("NOT_ACTIVE", "That quest is not active.")
	var quest := get_quest(quest_id)
	active[quest_id]["progress"] = int(active[quest_id].get("progress", 0)) + maxi(0, amount)
	var required := int(quest.get("required", 1))
	var finished := int(active[quest_id]["progress"]) >= required and required > 0
	return {
		"ok": true,
		"active_quests": active,
		"progress": int(active[quest_id]["progress"]),
		"required": required,
		"completed": finished,
	}


## Moves a finished quest into completed_quests and returns the reward summary.
static func complete(character: Dictionary, quest_id: String) -> Dictionary:
	var active: Dictionary = character.get("active_quests", {}).duplicate(true)
	var done: Array = (character.get("completed_quests", []) as Array).duplicate()
	if active.has(quest_id):
		active.erase(quest_id)
	if not done.has(quest_id):
		done.append(quest_id)
	var quest := get_quest(quest_id)
	var rewards: Dictionary = quest.get("rewards", {})
	return {
		"ok": true,
		"active_quests": active,
		"completed_quests": done,
		"reward_items": rewards.get("items", []),
		"reward_exp": int(rewards.get("exp", 0)),
		"reward_gold": int(rewards.get("gold", 0)),
	}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
