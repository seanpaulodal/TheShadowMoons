class_name Combatant
extends Node
## Anything that can fight: the player, the training dummy, later every enemy.
## It holds health, mana and stamina, the status effects, and the stats to fight
## with (base stats plus the current status effects). It decides nothing about
## how it looks: the owner reacts to the signals below.

signal damaged(result: Dictionary)     # also fires for misses (damage 0) and DoT ticks
signal healed(amount: int)
signal died
signal changed                          # health, stats or status effects changed

var display_name: String = ""
var level: int = 1
var team: String = ""
## Stats without status effects (for the player: class + build + equipment).
var base_stats: Dictionary = {}
## Stats to fight with right now: base stats plus status effects.
var stats: Dictionary = {}
var hp: int = 1
var mp: int = 0
var sp: int = 0
var element_profile: Dictionary = {}
## The weapon being used (see CombatProfile). Empty means bare hands.
var attack_profile: Dictionary = {}
## An immortal combatant (the training dummy) refills instead of dying.
var immortal: bool = false
var is_dead: bool = false
var status := StatusEffectManager.new()
## The fighter that hurt this one most recently (used to decide who gets the rewards).
var last_attacker: Combatant = null
## The scene object this fighter belongs to (the player body, an enemy, ...).
var owner_node: Node = null


func _init() -> void:
	status.changed.connect(_on_status_changed)


func setup(p_name: String, p_level: int, p_stats: Dictionary, p_team: String = "") -> void:
	display_name = p_name
	level = p_level
	team = p_team
	base_stats = p_stats.duplicate()
	_recalculate()
	hp = max_health()
	mp = max_mana()
	sp = max_stamina()
	is_dead = false
	changed.emit()


## Gives new base stats (for example after equipping gear). Health, mana and
## stamina keep their share of the maximum.
func set_base_stats(new_stats: Dictionary) -> void:
	var hp_share := float(hp) / maxf(1.0, float(max_health()))
	var mp_share := float(mp) / maxf(1.0, float(max_mana()))
	var sp_share := float(sp) / maxf(1.0, float(max_stamina()))
	base_stats = new_stats.duplicate()
	_recalculate()
	if not is_dead:
		hp = clampi(roundi(hp_share * max_health()), 1, max_health())
	mp = clampi(roundi(mp_share * max_mana()), 0, max_mana())
	sp = clampi(roundi(sp_share * max_stamina()), 0, max_stamina())
	changed.emit()


func max_health() -> int:
	return maxi(1, int(stats.get("max_health", 1)))


func max_mana() -> int:
	return maxi(0, int(stats.get("max_mana", 0)))


func max_stamina() -> int:
	return maxi(0, int(stats.get("max_stamina", 0)))


## Everything the damage calculator needs to know about this fighter.
func combat_info(skill_multiplier: float = 1.0) -> Dictionary:
	return {
		"stats": stats,
		"level": level,
		"weapon": attack_profile,
		"profile": element_profile,
		"skill_multiplier": skill_multiplier,
		"damage_taken_multiplier": status.damage_taken_multiplier(),
	}


## Takes damage that was already worked out (by DamageCalculator for attacks).
## Damage over time passes apply_taken_multiplier = true so "Shadow Mark" counts.
func take_damage(amount: int, result: Dictionary = {}, apply_taken_multiplier: bool = false) -> void:
	if is_dead:
		return
	var dealt := amount
	if apply_taken_multiplier:
		dealt = int(floor(float(amount) * status.damage_taken_multiplier()))
	dealt = maxi(0, dealt)
	hp -= dealt

	var report := result.duplicate()
	report["damage"] = dealt
	damaged.emit(report)

	if hp <= 0:
		if immortal:
			hp = max_health()
		else:
			hp = 0
			is_dead = true
			status.clear()
			died.emit()
	changed.emit()


## Announces an attack that did no damage (a miss or a parry).
func report_no_damage(result: Dictionary) -> void:
	damaged.emit(result)


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	var before := hp
	hp = mini(hp + amount, max_health())
	if hp != before:
		healed.emit(hp - before)
		changed.emit()


## Gives back health, mana or stamina ("health" | "mana" | "stamina").
## Returns how much was really restored (0 if already full).
func restore(resource: String, amount: int) -> int:
	if is_dead or amount <= 0:
		return 0
	match resource:
		"health":
			var before_hp := hp
			heal(amount)
			return hp - before_hp
		"mana":
			var before_mp := mp
			mp = mini(mp + amount, max_mana())
			if mp != before_mp:
				changed.emit()
			return mp - before_mp
		"stamina":
			var before_sp := sp
			sp = mini(sp + amount, max_stamina())
			if sp != before_sp:
				changed.emit()
			return sp - before_sp
	return 0


func revive(health_share: float = 1.0) -> void:
	is_dead = false
	hp = maxi(1, roundi(max_health() * clampf(health_share, 0.0, 1.0)))
	changed.emit()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	tick(delta)


## Moves status effects forward by `delta` seconds and applies their damage and healing.
func tick(delta: float) -> void:
	for event in status.update(delta, float(max_health())):
		if event["kind"] == "heal":
			heal(roundi(float(event["amount"])))
		else:
			take_damage(roundi(float(event["amount"])), {
				"outcome": "dot", "effect_id": event["effect_id"],
				"element": event["element"], "is_crit": false,
			}, true)


func _on_status_changed() -> void:
	_recalculate()
	changed.emit()


func _recalculate() -> void:
	stats = StatCalculator.apply_modifiers(base_stats, status.modifiers())
	hp = mini(hp, max_health())
