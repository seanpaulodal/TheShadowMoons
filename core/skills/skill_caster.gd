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
## The summons that are out now (see Summon).
var summons: Array = []

var _runner := AbilityRunner.new(self)

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


## Casts the class's special attack or ultimate (by ability id, "WAR_ULT_001").
## Needs it unlocked (by level), a free cooldown, enough of the class bar, and for
## most of them an enemy in range.
func cast_ability(ability_id: String, rolls: Dictionary = {}) -> Dictionary:
	var fighter := player.combatant
	var data := SkillDB.ability(ability_id)
	if data.is_empty():
		return _fail("UNKNOWN", "Unknown ability.")
	if fighter == null or fighter.is_dead:
		return _fail("DEAD", "You can't cast while dead.")
	if casting_skill != "":
		return _fail("BUSY", "Still casting.")
	var rank := SkillBook.ability_rank(Session.character, ability_id)
	if rank < 1:
		return _fail("LOCKED", "Reach level %d to use %s." % [int(data.get("unlock_level", 1)), str(data.get("ability_name", ""))])
	if not fighter.status.can_cast():
		return _fail("CANNOT_CAST", "You can't cast right now.")
	if not cooldowns.is_ready(ability_id):
		return _fail("COOLDOWN", "Not ready (%ds)." % ceili(cooldowns.remaining(ability_id)))
	var label := ClassResource.label(str(Session.character.get("class_id", "")))
	if AbilityEffects.requires_full_resource(ability_id) and fighter.mp < fighter.max_mana():
		return _fail("FULL_RESOURCE_NEEDED", "%s must be full." % label)
	var cost := AbilityEffects.cost(ability_id)
	if fighter.mp < cost:
		return _fail("NOT_ENOUGH_RESOURCE", "Not enough %s." % label)

	var target: Node3D = null
	if AbilityEffects.needs_target(ability_id):
		target = Targeting.pick(player, AbilityEffects.range_meters(ability_id), player.target)
		if target == null:
			return _fail("NO_TARGET", "No target in range.")
		player.set_target(target)

	fighter.mp -= cost
	fighter.changed.emit()
	cooldowns.start(ability_id, AbilityEffects.cooldown_at_rank(ability_id, rank))
	casting_skill = ability_id
	_cast_target = target
	_cast_rolls = rolls
	_cast_left = float(data.get("cast_time_seconds", 0.0))
	player.mark_combat()
	if target != null:
		player.face(target.global_position)
	cast_started.emit(ability_id)
	if instant or _cast_left <= 0.0:
		finish_cast()
	return {"ok": true, "skill_id": ability_id, "rank": rank, "cast_time": float(data.get("cast_time_seconds", 0.0))}


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
	if SkillDB.ability(skill_id).is_empty():
		_resolve(skill_id, target, rolls)
	else:
		_runner.run(skill_id, SkillBook.ability_rank(Session.character, skill_id), target, rolls)
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
		"summon":
			_summon_skill(skill_id, rank)
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
	var status := player.combatant.status
	var boost_id := status.find_with_key("next_skill_bonus")
	if boost_id != "" and SkillEffects.has_damage(skill_id):
		raw *= 1.0 + float(status.definition(boost_id)["next_skill_bonus"])
		status.remove(boost_id)
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


# ---------- summons ----------

func active_summons(summon_id: String = "") -> Array:
	summons = summons.filter(func(node: Variant) -> bool: return is_instance_valid(node) and not (node as Node).is_queued_for_deletion())
	if summon_id == "":
		return summons.duplicate()
	return summons.filter(func(node: Summon) -> bool: return node.summon_id == summon_id)


## Extra damage that an active aura summon gives all summons (0 = none).
func summon_attack_bonus() -> float:
	var best := 0.0
	for node in active_summons():
		best = maxf(best, float((node as Summon).definition.get("aura_attack_bonus", 0.0)))
	return best


func owner_power() -> float:
	var stats := player.combatant.stats
	return maxf(float(stats.get("atk_power", 0.0)), float(stats.get("magic_power", 0.0)))


func spawn_summon(summon_id: String, seconds: float, damage: float, index: int = 0, count: int = 1) -> Summon:
	var summon := Summon.new()
	var angle := TAU * float(index) / float(maxi(1, count))
	summon.setup(summon_id, player, seconds, damage, player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.5)
	player.get_parent().add_child(summon)
	summons.append(summon)
	return summon


func clear_summons() -> void:
	for node in summons:
		if is_instance_valid(node):
			(node as Node).queue_free()
	summons.clear()


## A summon skill: calls up to max_active_summons helpers, replacing the old ones
## of the same kind. Each hits for the skill's damage (or your power) x its percent.
func _summon_skill(skill_id: String, rank: int) -> void:
	var data := SkillEffects.effect(skill_id)
	var summon_id := str(data.get("summon_id", ""))
	var power := float(data.get("summon_attack_power_percent", 0.5)) * SkillDB.effect_multiplier(skill_id, rank)
	var base := SkillEffects.raw_damage(skill_id, rank, _attributes())
	var damage := base * power if base > 0.0 else owner_power() * power
	for old in active_summons(summon_id):
		(old as Node).queue_free()
	var count := maxi(1, int(data.get("max_active_summons", 1)))
	for index in count:
		spawn_summon(summon_id, float(data.get("duration_seconds", 30.0)), damage, index, count)
	say(SkillDB.skill_name(skill_id), Color("b9a0ff"))


func say(text: String, color: Color) -> void:
	_say(text, color)


func _say(text: String, color: Color) -> void:
	FloatingText.spawn(player.get_parent(), player.global_position + Vector3(0, 2.9, 0), text, color, 1.0)
