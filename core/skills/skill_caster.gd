class_name SkillCaster
extends Node
## Casts the player's skills. It checks everything (learned, silenced, cooldown,
## class bar, target in range), spends the cost, starts the cooldown, waits out the
## cast time, then does what the skill does: damage (one or several hits, one
## target or an area), execute, crowd control, damage over time, buffs, shields,
## heals and movement. Summons, ultimates and special attacks come later.
## It belongs to the player (PlayerController creates it).

signal cast_started(skill_id: String)
signal cast_finished(skill_id: String)
signal skill_hit(result: Dictionary)         # every damaging hit

var player: PlayerController
var cooldowns := PotionCooldowns.new()
## Tests only: resolve the skill the moment it is cast, and all hits at once.
var instant: bool = false
var casting_skill: String = ""

var _cast_left: float = 0.0
var _cast_target: Variant = null          # may be removed from the game before the cast ends
var _cast_rolls: Dictionary = {}


func setup(owner_player: PlayerController) -> void:
	player = owner_player


func is_casting() -> bool:
	return casting_skill != ""


## The skill on a slot ("skill_1" ... "skill_8"), or "".
func slot_skill(slot_name: String) -> String:
	return str(Session.character.get("skills", {}).get("slots", {}).get(slot_name, ""))


func rank_of(skill_id: String) -> int:
	return SkillBook.rank_of(SkillBook.normalize(Session.character.get("skills"), str(Session.character.get("class_id", ""))), skill_id)


func _physics_process(delta: float) -> void:
	cooldowns.update(delta)
	if casting_skill != "":
		_cast_left -= delta
		if _cast_left <= 0.0:
			finish_cast()


func cast_slot(slot_name: String, rolls: Dictionary = {}) -> Dictionary:
	var skill_id := slot_skill(slot_name)
	if skill_id == "":
		return _fail("NO_SKILL", "That slot is empty.")
	return cast(skill_id, rolls)


## Starts casting a skill. Returns {"ok": true, ...} or {"ok": false, "error", "message"}.
## Nothing is spent when it fails. `rolls` replaces random numbers (for tests).
func cast(skill_id: String, rolls: Dictionary = {}) -> Dictionary:
	var fighter := player.combatant
	if fighter == null or fighter.is_dead:
		return _fail("DEAD", "You can't cast while dead.")
	if casting_skill != "":
		return _fail("BUSY", "Still casting.")
	var rank := rank_of(skill_id)
	if rank < 1:
		return _fail("NOT_LEARNED", "You haven't learned that skill.")
	if not fighter.status.can_cast():
		return _fail("CANNOT_CAST", "You can't cast right now.")
	if not cooldowns.is_ready(skill_id):
		return _fail("COOLDOWN", "Not ready (%ds)." % ceili(cooldowns.remaining(skill_id)))
	if SkillEffects.effect_type(skill_id) == "summon":
		return _fail("NOT_READY", "Summons are coming in the next update.")

	var cost := roundi(SkillDB.cost_at_rank(skill_id, rank))
	if fighter.mp < cost:
		return _fail("NOT_ENOUGH_RESOURCE", "Not enough %s." % ClassResource.label(str(Session.character.get("class_id", ""))))

	var data := SkillDB.skill(skill_id)
	var target: Node3D = null
	if SkillEffects.needs_enemy(skill_id):
		target = Targeting.pick(player, float(data.get("skill_range_meters", 3.0)), player.target)
		if target == null:
			return _fail("NO_TARGET", "No target in range.")
		player.set_target(target)

	fighter.mp -= cost
	fighter.changed.emit()
	cooldowns.start(skill_id, SkillDB.cooldown_at_rank(skill_id, rank))
	casting_skill = skill_id
	_cast_target = target
	_cast_rolls = rolls
	_cast_left = float(data.get("skill_cast_time_seconds", 0.0))
	player.mark_combat()
	if target != null:
		player.face(target.global_position)
	cast_started.emit(skill_id)
	if instant or _cast_left <= 0.0:
		finish_cast()
	return {"ok": true, "skill_id": skill_id, "rank": rank, "cast_time": float(data.get("skill_cast_time_seconds", 0.0))}


## Ends the cast now and applies the skill. (Called when the cast time is up.)
func finish_cast() -> void:
	if casting_skill == "":
		return
	var skill_id := casting_skill
	var target: Variant = _cast_target
	var rolls := _cast_rolls
	casting_skill = ""
	_cast_target = null
	_cast_rolls = {}
	if player.is_dead():
		return
	_resolve(skill_id, target, rolls)
	cast_finished.emit(skill_id)


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}


func _attributes() -> Dictionary:
	return StatCalculator.attribute_totals(str(Session.character.get("class_id", "")), Session.character.get("attributes", {}))


# ---------- doing what the skill does ----------

func _resolve(skill_id: String, target: Variant, rolls: Dictionary) -> void:
	var rank := rank_of(skill_id)
	var fighter := player.combatant
	var source := {"from": fighter.display_name}
	match SkillEffects.effect_type(skill_id):
		"buff":
			if SkillEffects.buff_on_enemy(skill_id):
				for node in _targets_for(skill_id, target):
					var enemy: Combatant = node.get("combatant")
					enemy.last_attacker = fighter
					enemy.status.apply_custom(SkillEffects.buff_definition(skill_id, rank), source)
			else:
				fighter.status.apply_custom(SkillEffects.buff_definition(skill_id, rank), source)
				_say(SkillDB.skill_name(skill_id), Color("8fd0ff"))
		"defense":
			fighter.status.apply_custom(SkillEffects.defense_definition(skill_id, rank), source)
			_say(SkillDB.skill_name(skill_id), Color("8fd0ff"))
		"healing":
			var amount := SkillEffects.heal_amount(skill_id, rank, fighter.max_health())
			if SkillEffects.heal_over_time_seconds(skill_id) > 0.0:
				fighter.status.apply_custom(SkillEffects.hot_definition(skill_id, amount), source)
			else:
				var healed := fighter.restore("health", amount)
				_say("+%d" % healed, Color("7be07b"))
		"movement":
			_move(skill_id, target)
			if SkillEffects.has_damage(skill_id):
				var struck := Targeting.pick(player, float(SkillDB.skill(skill_id).get("skill_range_meters", 3.0)) + 1.5, player.target)
				if struck != null:
					_damage(skill_id, rank, struck, rolls)
		_:
			if target != null:
				_damage(skill_id, rank, target, rolls)


## The target and, for an area skill, the other enemies around it (up to max_targets).
func _targets_for(skill_id: String, primary: Variant) -> Array:
	var data := SkillDB.skill(skill_id)
	var radius := float(data.get("skill_area_radius_meters", 0.0))
	var maximum := int(data.get("skill_targeting", {}).get("max_targets", 1))
	var result: Array = []
	if Targeting.is_valid_target(primary):
		result.append(primary)
	if result.is_empty() or radius <= 0.0 or maximum <= 1:
		return result
	var others: Array = []
	for node in get_tree().get_nodes_in_group("targetable"):
		if node == primary or not (node is Node3D) or not Targeting.is_valid_target(node):
			continue
		var distance := Vector2(node.global_position.x - primary.global_position.x, node.global_position.z - primary.global_position.z).length()
		if distance <= radius:
			others.append([distance, node])
	others.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry in others:
		if result.size() >= maximum:
			break
		result.append(entry[1])
	return result


## Damage, execute, crowd control and damage over time on the target(s).
func _damage(skill_id: String, rank: int, primary: Variant, rolls: Dictionary) -> void:
	var raw := SkillEffects.raw_damage(skill_id, rank, _attributes())
	var hits := SkillEffects.hit_count(skill_id)
	var delay := 0.0 if instant else float(DataRegistry.get_config("skill_rules").get("hit_delay_seconds", 0.12))
	var targets := _targets_for(skill_id, primary)
	for index in hits:
		if index == 0 or delay <= 0.0:
			_hit_all(skill_id, rank, targets, raw, hits, index, rolls)
		else:
			get_tree().create_timer(delay * index).timeout.connect(_hit_all.bind(skill_id, rank, targets, raw, hits, index, rolls))


func _hit_all(skill_id: String, rank: int, targets: Array, raw: float, hits: int, index: int, rolls: Dictionary) -> void:
	if player == null or player.combatant == null or player.is_dead():
		return
	var fighter := player.combatant
	var kind := SkillEffects.effect_type(skill_id)
	for node in targets:
		if not Targeting.is_valid_target(node):
			continue
		var enemy: Combatant = node.get("combatant")
		if SkillEffects.has_damage(skill_id):
			var share := enemy.hp
			var params := {
				"raw": raw / float(hits), "damage_type": SkillEffects.damage_type(skill_id),
				"crit_bonus": SkillEffects.crit_bonus(skill_id), "power_multiplier": SkillEffects.power_multiplier(fighter),
				"damage_multiplier": SkillEffects.execute_multiplier(skill_id, rank, float(share) / float(maxi(1, enemy.max_health()))),
			}
			var result := CombatResolver.skill_hit(fighter, enemy, params, rolls)
			if result["ok"]:
				player.on_skill_hit(result, node)
				skill_hit.emit(result)
		if index == 0 and not enemy.is_dead:
			enemy.last_attacker = fighter
			var source := {"from": fighter.display_name}
			if kind == "crowd_control":
				var definition := SkillEffects.cc_definition(skill_id, rank)
				if not definition.is_empty():
					enemy.status.apply_custom(definition, source)
			elif kind == "damage_over_time":
				enemy.status.apply_custom(SkillEffects.dot_definition(skill_id, rank, raw), source)


## Dash, step back, or appear behind the target.
func _move(skill_id: String, target: Variant) -> void:
	var kind := SkillEffects.movement_kind(skill_id)
	var distance := SkillEffects.movement_distance(skill_id)
	var forward := player.facing_vector()
	var toward := forward
	if Targeting.is_valid_target(target):
		var flat := Vector3(target.global_position.x - player.global_position.x, 0.0, target.global_position.z - player.global_position.z)
		if flat.length() > 0.01:
			toward = flat.normalized()
	match kind:
		"backstep":
			player.dash(-toward, distance)
		"teleport_behind":
			if Targeting.is_valid_target(target):
				player.teleport_to(target.global_position + toward * 1.8)
				player.face(target.global_position)
			else:
				player.dash(forward, distance)
		_:
			player.dash(toward, distance)


func _say(text: String, color: Color) -> void:
	FloatingText.spawn(player.get_parent(), player.global_position + Vector3(0, 2.9, 0), text, color, 1.0)
