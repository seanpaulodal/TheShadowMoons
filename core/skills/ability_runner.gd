class_name AbilityRunner
extends RefCounted
## Does what an ultimate or a special attack does, once its cast is finished.
## (SkillCaster checks the cost, cooldown and target first.) Damage listed as
## "base_damage" is the TOTAL for the ability on each enemy: waves, rockets and
## repeated hits share it between them.

var caster: SkillCaster


func _init(owner_caster: SkillCaster) -> void:
	caster = owner_caster


func run(ability_id: String, rank: int, target: Variant, rolls: Dictionary) -> void:
	var player := caster.player
	var data := AbilityEffects.effect(ability_id)
	var power := AbilityEffects.power(ability_id, rank)
	var raw := AbilityEffects.raw_damage(ability_id, rank, caster._attributes())
	var kind := AbilityEffects.damage_type(ability_id)
	var fighter := player.combatant
	match AbilityEffects.behavior(ability_id):
		"kingdom_buff":
			_apply_self(ability_id, "buff", float(data.get("duration_seconds", 10.0)), {"modifiers": [
				{"stat": "atk_power", "flat": 0.0, "percent": float(data.get("attack_power_percent", 0.0)) * 100.0 * power},
				{"stat": "def_power", "flat": 0.0, "percent": float(data.get("defense_percent", 0.0)) * 100.0 * power}]})
		"transform":
			_apply_self(ability_id, "buff", float(data.get("duration_seconds", 10.0)), {
				"modifiers": [
					{"stat": "atk_power", "flat": 0.0, "percent": float(data.get("attack_power_percent", 0.0)) * 100.0 * power},
					{"stat": "atk_speed", "flat": 0.0, "percent": float(data.get("attack_speed_percent", 0.0)) * 100.0 * power}],
				"damage_taken_percent": -minf(float(data.get("damage_reduction_percent", 0.0)) * 100.0 * power, 90.0),
				"resource_drain_per_second": float(data.get("resource_drain_per_second", 0.0))})
		"stance":
			_apply_self(ability_id, "buff", float(data.get("duration_seconds", 8.0)), {"modifiers": [
				{"stat": "crit_chance", "flat": float(data.get("critical_chance_bonus_percent", 0.0)) * power, "percent": 0.0},
				{"stat": "atk_power", "flat": 0.0, "percent": float(data.get("ranged_damage_bonus_percent", 0.0)) * 100.0 * power}]})
		"bond":
			# The bond is meant to take an ally's damage. With no allies yet, it protects you.
			_apply_self(ability_id, "buff", float(data.get("duration_seconds", 8.0)), {
				"damage_taken_percent": -minf(float(data.get("damage_redirect_percent", 0.0)) * 100.0 * power, 90.0)})
		"next_spell":
			_apply_self(ability_id, "buff", float(data.get("duration_seconds", 8.0)), {
				"next_skill_bonus": float(data.get("next_spell_damage_bonus_percent", 0.0)) * power})
		"field":
			_field(ability_id, data, power, rolls)
		"waves":
			_waves(ability_id, data, raw, target, rolls)
		"multi_strike":
			_multi_strike(ability_id, data, raw, power, rolls)
		"barrage":
			_barrage(ability_id, data, raw, rolls)
		"legion":
			var seconds := float(data.get("duration_seconds", 20.0))
			var damage := caster.owner_power() * float(data.get("summon_attack_power_percent", 0.65)) * power
			for old in caster.active_summons("LEGION_SKELETON"):
				old.queue_free()
			var count := int(data.get("summon_count", 8))
			for index in count:
				caster.spawn_summon("LEGION_SKELETON", seconds, damage, index, count)
			caster.say(SkillDB.ability(ability_id)["ability_name"], Color("b9b4a0"))
		"execute_strike":
			var share := 1.0
			if Targeting.is_valid_target(target):
				var enemy: Combatant = (target as Node).get("combatant")
				share = float(enemy.hp) / float(maxi(1, enemy.max_health()))
			var bonus := float(data.get("bonus_damage_vs_missing_hp_percent", data.get("bonus_damage_vs_low_hp_percent", 0.0)))
			var multiplier := 1.0 + bonus * power if share * 100.0 <= float(data.get("execute_threshold_target_hp_percent", 0.0)) else 1.0
			_hit(target, raw, kind, multiplier, rolls)
		"lock_burst":
			var hits := int(data.get("hit_count", 6))
			var stacks := int(data.get("lock_on_stacks", 3))
			var growth := float(data.get("damage_per_stack_percent", 0.0))
			for index in hits:
				_later(0.1 * float(index), _hit.bind(target, raw / float(hits), kind, 1.0 + growth * float(mini(index, stacks)), rolls))
		"fists":
			var hits := int(data.get("hit_count", 12))
			var growth := float(data.get("combo_damage_growth_percent", 0.0))
			for index in hits:
				_later(0.08 * float(index), _hit.bind(target, raw / float(hits), kind, 1.0 + growth * float(index), rolls))
		"implosion":
			_implosion(ability_id, data, raw, target, rolls)
		"devour":
			var cursed: bool = _has_status(target, "curse")
			var multiplier := 1.0 + float(data.get("bonus_vs_cursed_percent", 0.0)) * power if cursed else 1.0
			var result := _hit(target, raw, kind, multiplier, rolls)
			if not result.is_empty():
				fighter.restore("health", roundi(float(result["damage"]) * float(data.get("heal_percent_of_damage", 0.0))))
				fighter.mp = mini(fighter.mp + int(data.get("soul_essence_gain", 0)), fighter.max_mana())
				fighter.changed.emit()
	player.mark_combat()


# ---------- the bigger ones ----------

## Rain, arrows or rockets: the damage is shared between the waves, which land
## one after another over the duration.
func _waves(ability_id: String, data: Dictionary, raw: float, target: Variant, rolls: Dictionary) -> void:
	var center: Vector3 = (target as Node3D).global_position if Targeting.is_valid_target(target) else caster.player.global_position
	var waves := maxi(1, int(data.get("waves", data.get("rocket_count", 1))))
	var seconds := float(data.get("duration_seconds", DataRegistry.get_config("skill_rules").get("wave_default_seconds", 3.0)))
	var radius := float(data.get("area_radius_meters", 8.0))
	for index in waves:
		_later(seconds * float(index) / float(waves), _wave.bind(center, radius, raw / float(waves), AbilityEffects.damage_type(ability_id), rolls))


func _wave(center: Vector3, radius: float, raw: float, kind: String, rolls: Dictionary) -> void:
	if caster.player == null or caster.player.is_dead():
		return
	for node in _enemies_near(center, radius):
		_hit(node, raw, kind, 1.0, rolls)


func _multi_strike(ability_id: String, data: Dictionary, raw: float, power: float, rolls: Dictionary) -> void:
	var targets := _enemies_near(caster.player.global_position, AbilityEffects.range_meters(ability_id), int(data.get("max_targets", 5)))
	var hits := int(data.get("hit_count", 8))
	var kind := AbilityEffects.damage_type(ability_id)
	for index in hits:
		for node in targets:
			var marked: bool = _has_status(node, "shadow_mark")
			var multiplier := 1.0 + float(data.get("bonus_vs_marked_percent", 0.0)) * power if marked else 1.0
			_later(0.1 * float(index), _hit.bind(node, raw / float(hits), kind, multiplier, rolls))


func _barrage(ability_id: String, data: Dictionary, raw: float, rolls: Dictionary) -> void:
	var hits := int(data.get("hit_count", 10))
	var growth := float(data.get("combo_bonus_per_hit", 0.0))
	var radius := float(data.get("area_radius_meters", 5.0))
	for index in hits:
		_later(0.12 * float(index), _wave.bind(caster.player.global_position, radius, raw / float(hits) * (1.0 + growth * float(index)), AbilityEffects.damage_type(ability_id), rolls))


## A divine field around you: heals you, cuts the damage you take, hurts enemies inside.
func _field(ability_id: String, data: Dictionary, power: float, rolls: Dictionary) -> void:
	var fighter := caster.player.combatant
	var seconds := maxf(1.0, float(data.get("duration_seconds", 10.0)))
	var heal_total := float(fighter.max_health()) * float(data.get("heal_percent_max_hp", 0.0)) * power
	_apply_self(ability_id, "hot", seconds, {
		"tick": {"interval": 1.0, "flat": heal_total / seconds, "percent_max_health": 0.0, "element": "holy", "heal": true},
		"damage_taken_percent": -minf(float(data.get("damage_reduction_percent", 0.0)) * 100.0 * power, 90.0)})
	var damage: Dictionary = AbilityEffects.data(ability_id).get("damage", {})
	var total := (float(data.get("enemy_damage", 0.0)) + float(caster._attributes().get(str(damage.get("scaling_attribute", "")).to_lower(), 0)) * float(damage.get("attribute_scaling", 0.0))) * power
	var center := caster.player.global_position
	var ticks := int(seconds)
	for index in ticks:
		_later(float(index) + 1.0, _wave.bind(center, float(data.get("area_radius_meters", 10.0)), total / float(ticks), "holy", rolls))


## Pulls enemies in toward the centre, then everything inside takes the blast.
## Needs the class bar full, and empties it.
func _implosion(ability_id: String, data: Dictionary, raw: float, target: Variant, rolls: Dictionary) -> void:
	var player := caster.player
	var center: Vector3 = (target as Node3D).global_position if Targeting.is_valid_target(target) else player.global_position
	var radius := float(data.get("area_radius_meters", 9.0))
	var pull := clampf(float(data.get("pull_strength", 0.0)), 0.0, 1.0)
	for node in _enemies_near(center, radius):
		var spot := (node as Node3D).global_position
		var flat := Vector3(center.x, spot.y, center.z)
		(node as Node3D).global_position = flat.lerp(spot, 1.0 - pull)
	_wave(center, radius, raw, AbilityEffects.damage_type(ability_id), rolls)
	player.combatant.mp = 0                     # all of it is spent (after the hits, which give some back)
	player.combatant.changed.emit()


# ---------- helpers ----------

func _has_status(node: Variant, effect_id: String) -> bool:
	if not Targeting.is_valid_target(node):
		return false
	var enemy: Combatant = (node as Node).get("combatant")
	return enemy.status.has(effect_id)


func _apply_self(ability_id: String, kind: String, seconds: float, extra: Dictionary) -> void:
	var definition := {"effect_id": "ability_%s" % ability_id, "name": str(AbilityEffects.data(ability_id).get("ability_name", ability_id)),
			"kind": kind, "duration": seconds, "stacking": "refresh", "max_stacks": 1, "cleansable": false}
	definition.merge(extra, true)
	caster.player.combatant.status.apply_custom(definition, {"from": caster.player.combatant.display_name})
	caster.say(str(definition["name"]), Color("ffd23f"))


## Every living enemy within `radius` of a point, nearest first (up to `limit`).
func _enemies_near(center: Vector3, radius: float, limit: int = 999) -> Array:
	var found: Array = []
	for node in caster.get_tree().get_nodes_in_group("targetable"):
		if not (node is Node3D) or not Targeting.is_valid_target(node):
			continue
		var distance := Vector2(node.global_position.x - center.x, node.global_position.z - center.z).length()
		if distance <= radius:
			found.append([distance, node])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array = []
	for entry in found:
		if result.size() >= limit:
			break
		result.append(entry[1])
	return result


## One hit on one enemy. Returns the result, or {} if the enemy is gone.
func _hit(node: Variant, raw: float, damage_type: String, multiplier: float, rolls: Dictionary) -> Dictionary:
	var player := caster.player
	if player == null or not is_instance_valid(player) or player.is_dead() or not Targeting.is_valid_target(node):
		return {}
	var enemy: Combatant = (node as Node).get("combatant")
	var params := {"raw": raw, "damage_type": damage_type, "crit_bonus": 0.0,
			"power_multiplier": SkillEffects.power_multiplier(player.combatant), "damage_multiplier": multiplier}
	var result := CombatResolver.skill_hit(player.combatant, enemy, params, rolls)
	if not result["ok"]:
		return {}
	player.on_skill_hit(result, node)
	caster.skill_hit.emit(result)
	return result


func _later(seconds: float, action: Callable) -> void:
	if caster.instant or seconds <= 0.0:
		action.call()
	else:
		caster.get_tree().create_timer(seconds).timeout.connect(action)
