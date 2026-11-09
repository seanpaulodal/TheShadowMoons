class_name ElementalSystem
extends RefCounted
## The one place that knows how elements affect each other. Weaknesses and
## resistances are NOT stored per enemy: a target's own element (for an enemy,
## its status_ELEM) is looked up in the chart in TSM_Element_Rules.json.
## Unknown element names count as neutral, so nothing breaks while the chart grows.


static func _rules() -> Dictionary:
	return DataRegistry.get_config("element_rules")


## Turns any element text into known element ids.
## "Shadow/Fire" -> ["dark", "fire"], "Lightning" -> ["shock"], "N/A" -> [].
static func canonical(raw: String) -> Array:
	var rules := _rules()
	var chart: Dictionary = rules.get("elements", {})
	var aliases: Dictionary = rules.get("aliases", {})
	var found: Array = []
	var text := raw.strip_edges().to_lower().replace("/", " ").replace(",", " ")
	for token in text.split(" ", false):
		var element := ""
		if chart.has(token):
			element = token
		elif aliases.has(token):
			element = str(aliases[token])
		if element != "" and not found.has(element):
			found.append(element)
	return found


## What a target with this element is weak to, resists, or is immune to.
## {"elements": [...], "weak": [...], "resist": [...], "immune": [...]}
static func profile_for(raw_element: String) -> Dictionary:
	var chart: Dictionary = _rules().get("elements", {})
	var elements := canonical(raw_element)
	var weak: Array = []
	var resist: Array = []
	var immune: Array = []
	for element in elements:
		var entry: Dictionary = chart.get(element, {})
		for other in entry.get("weak_to", []):
			if not weak.has(other):
				weak.append(other)
		for other in entry.get("resists", []):
			if not resist.has(other):
				resist.append(other)
		for other in entry.get("immune_to", []):
			if not immune.has(other):
				immune.append(other)
	# Something that is both weak to and resistant to an element is neutral to it.
	for other in weak.duplicate():
		if resist.has(other):
			weak.erase(other)
			resist.erase(other)
	return {"elements": elements, "weak": weak, "resist": resist, "immune": immune}


## The profile of one enemy: a hand-set override if there is one, otherwise
## its own element.
static func profile_for_enemy(enemy_id: String) -> Dictionary:
	var overrides: Dictionary = _rules().get("enemy_overrides", {})
	if overrides.has(enemy_id):
		return profile_for(str(overrides[enemy_id].get("element", "")))
	return profile_for(str(DataRegistry.get_enemy(enemy_id).get("status_ELEM", "")))


## Damage multiplier of an attack element against a target profile.
static func multiplier(attack_element: String, profile: Dictionary) -> float:
	var attack := canonical(attack_element)
	if attack.is_empty():
		return 1.0
	var element: String = attack[0]
	if element == "physical":
		return 1.0
	var values: Dictionary = _rules().get("multipliers", {})
	if (profile.get("immune", []) as Array).has(element):
		return float(values.get("immune", 0.0))
	if (profile.get("weak", []) as Array).has(element):
		return float(values.get("weak", 1.5))
	if (profile.get("resist", []) as Array).has(element):
		return float(values.get("resist", 0.5))
	return 1.0


## Element names used by enemies that the chart does not know yet. They count
## as neutral until you add them to the chart or the aliases.
static func unknown_enemy_elements() -> Array:
	var unknown: Array = []
	var rules := _rules()
	var chart: Dictionary = rules.get("elements", {})
	var aliases: Dictionary = rules.get("aliases", {})
	var ignored: Array = rules.get("ignored_words", [])
	for enemy_id in DataRegistry.get_ids("enemies"):
		var text := str(DataRegistry.get_enemy(enemy_id).get("status_ELEM", "")).strip_edges().to_lower()
		for token in text.replace("/", " ").replace(",", " ").split(" ", false):
			if token in ["n", "a", "n/a"] or ignored.has(token) or chart.has(token) or aliases.has(token) or unknown.has(token):
				continue
			unknown.append(token)
	unknown.sort()
	return unknown
