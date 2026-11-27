class_name PlayerController
extends CharacterBody3D
## The player's body: walking, attacking, gravity, and the follow camera.
## Stats come from CharacterStats (class, level, attribute points and worn gear),
## and status effects (slow, stun, ...) change them while they last.
##
## Controls: WASD / arrow keys or the touch joystick to move, right mouse button
## or dragging the right side of the screen to turn the camera, mouse wheel to
## zoom, Space / F or the ATK button to attack.

signal stats_changed
## An attack happened (hit, miss, parry). Carries the result dictionary.
signal attacked(result: Dictionary)
signal attack_failed(reason: String)
signal target_changed(target: Node3D)
signal died
signal revived

const GRAVITY := 14.0              # reference value from the design document
const ACCELERATION := 60.0
const TURN_SPEED := 12.0
const FALLBACK_SPEED := 7.0
const FALLBACK_RANGE := 3.0
const FALL_LIMIT := -20.0
const MOUSE_LOOK_SENSITIVITY := 0.004
const PITCH_MIN := -1.3
const PITCH_MAX := -0.05
const DISTANCE_MIN := 3.0
const DISTANCE_MAX := 12.0

const ACTION_KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack": [KEY_SPACE, KEY_F],
	"interact": [KEY_E],
	"special": [KEY_Q], "ultimate": [KEY_R],
	"skill_1": [KEY_1], "skill_2": [KEY_2], "skill_3": [KEY_3], "skill_4": [KEY_4],
	"skill_5": [KEY_5], "skill_6": [KEY_6], "skill_7": [KEY_7], "skill_8": [KEY_8],
}

## Stats from the character's build and gear (see CharacterStats), before status effects.
var stats: Dictionary = {}
## Health, mana, stamina, status effects and the stats to fight with.
var combatant: Combatant
## Who the next attack goes to. Set automatically.
var target: Node3D
## Optional: touch controls to read the joystick, camera drag and attack button from.
var controls: TouchControls
## Used by tests to push the character without a keyboard or touch screen.
var move_override: Vector2 = Vector2.ZERO
var spawn_position: Vector3 = Vector3(0, 1, 0)

## Casts the skills on the eight slots (see SkillCaster).
var skills: SkillCaster

## One cooldown per potion (see PotionCooldowns).
var potion_cooldowns := PotionCooldowns.new()
## Tests only: a fixed "now" in Unix seconds for elixirs. -1 means the real clock.
var clock_override: int = -1

var _autopot_timer: float = 0.0
var _elixir_timer: float = 0.0
var _vitals_timer: float = 0.0
var _vitals_dirty: bool = false
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_left: float = 0.0
var _dead: bool = false
var _combat_clock: float = 99.0      # seconds since the last fight action
var _regen_pools := {"hp": 0.0, "mp": 0.0, "sp": 0.0}
var _nameplate: Label3D
var _extra_modifiers: Array = []
var _mounted: bool = false
var _combatant_ready: bool = false
var _attack_cooldown: float = 0.0
var _yaw: float = 0.0
var _pitch: float = -0.4
var _distance: float = 6.5
var _mouse_look: Vector2 = Vector2.ZERO
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D


func _ready() -> void:
	_ensure_input_actions()
	add_to_group("player")
	platform_floor_layers = 0      # never ride along on top of enemies or other bodies
	_build_body()
	_build_camera()
	combatant = Combatant.new()
	add_child(combatant)
	combatant.owner_node = self
	skills = SkillCaster.new()
	skills.setup(self)
	add_child(skills)
	refresh_stats()
	combatant.damaged.connect(_on_combatant_damaged)
	combatant.died.connect(_on_died)
	_apply_saved_vitals()
	combatant.changed.connect(func() -> void: _vitals_dirty = true)
	Session.character_changed.connect(_on_character_changed)
	Session.reward_granted.connect(_on_kill_reward)
	global_position = spawn_position


## Recalculates the stats from the saved character: its class, level and
## allocated attribute points, plus everything it wears. Called automatically
## when the character changes. `extra_modifiers` is for temporary bonuses.
func refresh_stats(extra_modifiers: Array = [], mounted: bool = false) -> void:
	_extra_modifiers = extra_modifiers
	_mounted = mounted
	var result := CharacterStats.compute(Session.character, _mounted, _extra_modifiers)
	if result["ok"]:
		stats = result["stats"]
	else:
		stats = {"move_speed": FALLBACK_SPEED, "max_health": 1}

	if combatant != null:
		if not _combatant_ready:
			combatant.setup(str(Session.character.get("name", "Player")),
					int(Session.character.get("level", 1)), stats, "player")
			combatant.mp = ClassResource.start_value(str(Session.character.get("class_id", "")), combatant.max_mana())
			_combatant_ready = true
		else:
			combatant.level = int(Session.character.get("level", 1))
			combatant.set_base_stats(stats)
		combatant.attack_profile = CombatProfile.for_character(Session.character)
	stats_changed.emit()


## Riding a mount adds the mount's bonus (for example speed).
func set_mounted(riding: bool) -> void:
	refresh_stats(_extra_modifiers, riding)


func _on_character_changed() -> void:
	refresh_stats(_extra_modifiers, _mounted)
	if _nameplate != null:
		_nameplate.text = "%s\n%s  Lv %d" % [
				str(Session.character.get("name", "?")),
				str(Session.character.get("class_id", "?")).capitalize(),
				int(Session.character.get("level", 1))]


func is_dead() -> bool:
	return _dead


## Uses a potion, food or elixir from the bag. A potion restores health, mana or
## stamina and is used up; it is refused while that potion is cooling down or when
## the bar is already full. An elixir starts regenerating. Returns
## {"ok", "resource", "amount"} or {"ok": false, "error", "message"}.
func use_consumable(item_id: String) -> Dictionary:
	if combatant == null or combatant.is_dead:
		return {"ok": false, "error": "DEAD", "message": "You can't use items right now."}
	var effect := ItemDB.consumable_effect(item_id)
	if effect.is_empty():
		return {"ok": false, "error": "NOT_USABLE", "message": "That can't be used."}
	if Inventory.count(Session.character["inventory"], item_id) < 1:
		return {"ok": false, "error": "NOT_FOUND", "message": "You don't have that."}
	if not potion_cooldowns.is_ready(item_id):
		return {"ok": false, "error": "COOLDOWN",
				"message": "Not ready yet (%ds)." % ceili(potion_cooldowns.remaining(item_id))}
	if str(effect["resource"]) == "elixir":
		return _use_elixir(item_id)

	var room := 0
	match str(effect["resource"]):
		"health":
			room = combatant.max_health() - combatant.hp
		"mana":
			room = combatant.max_mana() - combatant.mp
		"stamina":
			room = combatant.max_stamina() - combatant.sp
	if room <= 0:
		return {"ok": false, "error": "ALREADY_FULL", "message": "Already full."}

	Session.remove_item(item_id, 1)
	var restored := combatant.restore(str(effect["resource"]), int(effect["amount"]))
	potion_cooldowns.start(item_id)
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 2.9, 0),
			"+%d %s" % [restored, ItemInfo.RESOURCE_LABELS.get(effect["resource"], "")],
			Color("7be07b"), 0.9)
	return {"ok": true, "resource": effect["resource"], "amount": restored}


## Uses whatever potion is on a quick-use slot ("health", "mana" or "stamina").
func use_quick_slot(resource: String) -> Dictionary:
	var assigned := str(Session.character.get("settings", {}).get("quick_slots", {}).get(resource, ""))
	if assigned == "":
		return {"ok": false, "error": "NO_SLOT", "message": "Set a potion for this slot in your Bag."}
	if Inventory.count(Session.character["inventory"], assigned) < 1:
		return {"ok": false, "error": "NO_POTION", "message": "Out of %s." % ItemDB.display_name(assigned)}
	return use_consumable(assigned)


func _use_elixir(item_id: String) -> Dictionary:
	var result := Session.activate_elixir(item_id, _now())
	if not result["ok"]:
		return result
	_elixir_timer = 0.0
	potion_cooldowns.start(item_id, 1.0)
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 2.9, 0), "Elixir active",
			Color("ffd23f"), 1.0)
	return {"ok": true, "resource": "elixir", "amount": 0}


## Time as Unix seconds (a test can fix it with clock_override).
func _now() -> int:
	return clock_override if clock_override >= 0 else int(Time.get_unix_time_from_system())


func now_unix() -> int:
	return _now()


## Seconds since the last fight action (attacking or being hit).
func seconds_since_combat() -> float:
	return _combat_clock


## Moves the player to a spot on the ground (waypoint teleport).
func teleport_to(point: Vector3) -> void:
	global_position = Vector3(point.x, 0.2, point.z)
	velocity = Vector3.ZERO
	target = null
	target_changed.emit(null)


## Drinks potions by itself when health or mana falls under the player's limits.
func _run_autopot(delta: float) -> void:
	var rules: Dictionary = DataRegistry.get_config("consumable_rules").get("auto_pot", {})
	_autopot_timer += delta
	if _autopot_timer < float(rules.get("check_interval", 0.25)):
		return
	_autopot_timer = 0.0
	var settings: Dictionary = Session.character.get("settings", {})
	if not (settings.get("auto_hp", false) or settings.get("auto_mp", false)):
		return
	var picks := AutoPot.choose({
		"hp": combatant.hp, "max_hp": combatant.max_health(),
		"mp": combatant.mp, "max_mp": combatant.max_mana(),
		"settings": settings,
		"inventory": Session.character.get("inventory", []),
		"cooldowns": potion_cooldowns,
	})
	for pick in picks:
		use_consumable(str(pick["item_id"]))


## An active elixir restores a percent of the maximum every few seconds.
func _tick_elixir(delta: float) -> void:
	var elixir: Dictionary = Session.character.get("elixir", {})
	if elixir.is_empty():
		_elixir_timer = 0.0
		return
	if not ElixirRules.is_active(elixir, _now()):
		Session.clear_elixir()
		return
	_elixir_timer += delta
	var every := ElixirRules.tick_seconds()
	if _elixir_timer < every:
		return
	_elixir_timer -= every
	var amounts := ElixirRules.tick_amounts(elixir, combatant.max_health(), combatant.max_mana(), combatant.max_stamina())
	combatant.restore("health", int(amounts["hp"]))
	combatant.restore("mana", int(amounts["mp"]))
	combatant.restore("stamina", int(amounts["sp"]))


## Saves health, mana and stamina every few seconds (only when they changed).
func _remember_vitals(delta: float) -> void:
	_vitals_timer += delta
	if _vitals_timer < 3.0 or not _vitals_dirty:
		return
	_vitals_timer = 0.0
	_vitals_dirty = false
	Session.record_vitals(combatant.hp, combatant.mp, combatant.sp)


## On entering the game: start with the health you left with, plus what an active
## elixir restored while you were away (at most offline_cap_hours of it).
func _apply_saved_vitals() -> void:
	var saved: Dictionary = Session.character.get("vitals", {})
	if saved.is_empty():
		return
	var hp := int(saved.get("hp", combatant.max_health()))
	var mp := int(saved.get("mp", combatant.max_mana()))
	var sp := int(saved.get("sp", combatant.max_stamina()))
	if hp <= 0:
		hp = combatant.max_health()      # you do not come back dead

	var elixir: Dictionary = Session.character.get("elixir", {})
	var last_seen := int(Time.get_unix_time_from_datetime_string(str(Session.character.get("updated_at", ""))))
	if not elixir.is_empty() and last_seen > 0:
		var ticks := ElixirRules.ticks_between(elixir, last_seen, _now(), true)
		if ticks > 0:
			var amounts := ElixirRules.tick_amounts(elixir, combatant.max_health(), combatant.max_mana(), combatant.max_stamina())
			hp += int(amounts["hp"]) * ticks
			mp += int(amounts["mp"]) * ticks
			sp += int(amounts["sp"]) * ticks
	combatant.set_vitals(hp, mp, sp)


## Comes back to life at the starting point with full health.
func revive() -> void:
	_dead = false
	combatant.status.clear()
	combatant.revive(1.0)
	global_position = spawn_position
	velocity = Vector3.ZERO
	_combat_clock = 99.0
	revived.emit()


func _on_died() -> void:
	_dead = true
	if skills != null:
		skills.clear_summons()
	target = null
	target_changed.emit(null)
	died.emit()


func _on_combatant_damaged(result: Dictionary) -> void:
	_combat_clock = 0.0
	if int(result.get("damage", 0)) > 0 and str(result.get("outcome", "hit")) != "dot":
		gain_resource("hit_taken")
	var at := global_position + Vector3(0, 2.9, 0)
	var outcome := str(result.get("outcome", "hit"))
	if outcome == "miss":
		FloatingText.spawn(get_parent(), at, "MISS", Color("b8b0c8"), 0.8)
	elif outcome == "parry":
		FloatingText.spawn(get_parent(), at, "PARRY", Color("7fb4ff"), 0.8)
	elif int(result.get("damage", 0)) > 0:
		var crit: bool = result.get("is_crit", false)
		FloatingText.spawn(get_parent(), at, ("-%d!" if crit else "-%d") % int(result["damage"]),
				Color("ff5a5a"), 1.3 if crit else 1.0)


## Slowly recovers health, mana and stamina when nothing has happened for a while.
## (Placeholder until potions and elixirs are in.)
func _regenerate(delta: float) -> void:
	var rules: Dictionary = DataRegistry.get_config("combat_rules").get("out_of_combat_regen", {})
	if _combat_clock < float(rules.get("delay_seconds", 5.0)):
		return
	var rate := float(rules.get("percent_per_second", 1.0)) / 100.0
	var changed := false

	_regen_pools["hp"] += float(combatant.max_health()) * rate * delta
	var whole_hp := int(_regen_pools["hp"])
	if whole_hp > 0:
		_regen_pools["hp"] -= whole_hp
		combatant.heal(whole_hp)
	_regen_pools["sp"] += float(combatant.max_stamina()) * rate * delta
	var whole_sp := int(_regen_pools["sp"])
	if whole_sp > 0:
		_regen_pools["sp"] -= whole_sp
		combatant.sp = mini(combatant.sp + whole_sp, combatant.max_stamina())
		changed = true
	if changed:
		combatant.changed.emit()


## The class bar (the MP bar) refills, builds up or drains by the rules of the class.
func _update_class_bar(delta: float) -> void:
	var class_id := str(Session.character.get("class_id", ""))
	var per_second := ClassResource.rate(class_id, _combat_clock)
	var drain := combatant.status.sum_key("resource_drain_per_second")
	if drain > 0.0:
		per_second = -drain                      # while transformed the bar only drains
		if combatant.mp <= 0:
			for effect_id in combatant.status.active_ids():
				if combatant.status.definition(str(effect_id)).has("resource_drain_per_second"):
					combatant.status.remove(str(effect_id))     # the transformation ends when the bar is empty
	if per_second == 0.0:
		return
	_regen_pools["mp"] += per_second * delta
	var whole := int(_regen_pools["mp"])
	if whole != 0:
		_regen_pools["mp"] -= whole
		var before := combatant.mp
		combatant.mp = clampi(combatant.mp + whole, 0, combatant.max_mana())
		if combatant.mp != before:
			combatant.changed.emit()


## Adds to (or takes from) the class bar after a fight event: "hit", "hit_taken", "kill".
func gain_resource(event: String) -> void:
	var amount := ClassResource.gain(str(Session.character.get("class_id", "")), event)
	if amount > 0.0 and combatant != null and not combatant.is_dead:
		combatant.mp = mini(combatant.mp + roundi(amount), combatant.max_mana())
		combatant.changed.emit()


func _on_kill_reward(summary: Dictionary) -> void:
	if int(summary.get("exp", 0)) > 0 or int(summary.get("gold", 0)) > 0:
		gain_resource("kill")


## A summon of mine hit something. It counts as my fight (and my kill).
func on_summon_hit(result: Dictionary, victim: Node3D) -> void:
	_combat_clock = 0.0
	if result.get("killed", false) and victim == target:
		target = null
		target_changed.emit(null)


## A skill of mine hit something.
func on_skill_hit(result: Dictionary, victim: Node3D) -> void:
	_combat_clock = 0.0
	gain_resource("hit")
	if result.get("killed", false) and victim == target:
		target = null
		target_changed.emit(null)


## Resets the "in a fight" timer (casting counts as fighting).
func mark_combat() -> void:
	_combat_clock = 0.0


func set_target(node: Node3D) -> void:
	if node != target:
		target = node
		target_changed.emit(target)


## Turns to look at a point (ground only).
func face(point: Vector3) -> void:
	var toward := point - global_position
	if Vector2(toward.x, toward.z).length() > 0.01:
		_model.rotation.y = atan2(-toward.x, -toward.z)


## The way the character faces, as a flat direction.
func facing_vector() -> Vector3:
	var yaw := _model.rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## A quick dash: runs over a fraction of a second, stopping at walls.
func dash(direction: Vector3, distance: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01 or distance <= 0.0:
		return
	var speed := float(DataRegistry.get_config("skill_rules").get("dash_speed", 28.0))
	_dash_direction = flat.normalized() * speed
	_dash_left = distance / speed


## Walking speed right now, including slows and haste.
func move_speed() -> float:
	if combatant != null and not combatant.stats.is_empty():
		return float(combatant.stats.get("move_speed", FALLBACK_SPEED))
	return float(stats.get("move_speed", FALLBACK_SPEED))


func attack_range() -> float:
	if combatant != null:
		return float(combatant.stats.get("attack_range", FALLBACK_RANGE))
	return FALLBACK_RANGE


func facing_yaw() -> float:
	return _yaw


func set_facing_yaw(value: float) -> void:
	_yaw = value


## One basic attack on the nearest target in range. `rolls` replaces the random
## numbers (for tests). Returns the result dictionary; {"ok": false, "error": CODE}
## when nothing happened.
func try_attack(rolls: Dictionary = {}) -> Dictionary:
	if combatant == null or combatant.is_dead:
		return {"ok": false, "error": "DEAD"}
	if _attack_cooldown > 0.0:
		return {"ok": false, "error": "COOLDOWN"}
	if skills != null and skills.is_casting():
		return {"ok": false, "error": "CASTING"}
	if not combatant.status.can_attack():
		attack_failed.emit("You can't attack right now")
		return {"ok": false, "error": "CANNOT_ATTACK"}

	var picked := Targeting.pick(self, attack_range(), target)
	if picked != target:
		target = picked
		target_changed.emit(target)
	if picked == null:
		attack_failed.emit("No target in range")
		return {"ok": false, "error": "NO_TARGET"}

	# Face the target.
	var toward := picked.global_position - global_position
	if Vector2(toward.x, toward.z).length() > 0.01:
		_model.rotation.y = atan2(-toward.x, -toward.z)

	var result := CombatResolver.attack(combatant, picked.get("combatant"), 1.0, rolls)
	if not result["ok"]:
		return result

	var rules := DataRegistry.get_config("combat_rules")
	var speed_floor := float(rules.get("attack_button_cooldown_floor", 0.2))
	_attack_cooldown = 1.0 / maxf(float(combatant.stats.get("atk_speed", 1.0)), speed_floor)

	# A small punch so the swing can be seen.
	_model.scale = Vector3.ONE * 1.15
	create_tween().tween_property(_model, "scale", Vector3.ONE, 0.15)

	_combat_clock = 0.0
	if str(result.get("outcome", "")) == "hit":
		gain_resource("hit")
	attacked.emit(result)
	if result.get("killed", false):
		target = null
		target_changed.emit(null)
	return result


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_combat_clock += delta
	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCELERATION * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_regenerate(delta)
	_update_class_bar(delta)
	potion_cooldowns.update(delta)
	_run_autopot(delta)
	_tick_elixir(delta)
	_remember_vitals(delta)

	var input := _read_move_input().limit_length(1.0)
	if combatant != null and not combatant.status.can_move():
		input = Vector2.ZERO
	var direction := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	var target_velocity := direction * move_speed()
	if _dash_left > 0.0:
		_dash_left -= delta
		target_velocity = _dash_direction
		velocity.x = _dash_direction.x
		velocity.z = _dash_direction.z

	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta)
	velocity.y -= GRAVITY * delta
	move_and_slide()

	# Turn the model toward where we are walking.
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > 0.5:
		var wanted := atan2(-velocity.x, -velocity.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, wanted, clampf(TURN_SPEED * delta, 0.0, 1.0))

	# Holding the attack button (or key) keeps attacking.
	var wants_attack := Input.is_action_pressed("attack") or (controls != null and controls.attack_held)
	if wants_attack and _attack_cooldown <= 0.0:
		try_attack()

	# Drop the target when it walks away or dies.
	if target != null and (not Targeting.is_valid_target(target) or Targeting.distance(self, target) > attack_range() + 4.0):
		target = null
		target_changed.emit(null)

	if global_position.y < FALL_LIMIT:
		global_position = spawn_position
		velocity = Vector3.ZERO


func _process(_delta: float) -> void:
	var look := _mouse_look
	_mouse_look = Vector2.ZERO
	if controls != null:
		look += controls.consume_look_delta()
	if look != Vector2.ZERO:
		_yaw -= look.x
		_pitch = clampf(_pitch - look.y, PITCH_MIN, PITCH_MAX)
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position.z = _distance


func _unhandled_input(event: InputEvent) -> void:
	for kind in ["special", "ultimate"]:
		if event.is_action_pressed(kind) and skills != null:
			var ability: Dictionary = SkillDB.special_for_class(str(Session.character.get("class_id", ""))) if kind == "special" \
					else SkillDB.ultimate_for_class(str(Session.character.get("class_id", "")))
			var result := skills.cast_ability(str(ability.get("ability_id", "")))
			if not result["ok"]:
				attack_failed.emit(str(result.get("message", "")))
			return
	for slot_name in SkillDB.SLOT_NAMES:
		if event.is_action_pressed(slot_name) and skills != null:
			var result := skills.cast_slot(slot_name)
			if not result["ok"]:
				attack_failed.emit(str(result.get("message", "")))
			return
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_mouse_look += event.relative * MOUSE_LOOK_SENSITIVITY
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.5, DISTANCE_MIN, DISTANCE_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.5, DISTANCE_MIN, DISTANCE_MAX)


func _read_move_input() -> Vector2:
	if move_override != Vector2.ZERO:
		return move_override
	if controls != null and controls.move_vector != Vector2.ZERO:
		return controls.move_vector
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


# ---------- building the body and camera ----------

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.8
	shape.shape = capsule_shape
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	_model = Node3D.new()
	add_child(_model)

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("7a4bd1")
	capsule.material = body_material
	body.mesh = capsule
	body.position = Vector3(0, 0.9, 0)
	_model.add_child(body)

	# A small gold "nose" shows which way the character faces (forward is -Z).
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.22, 0.22, 0.4)
	var nose_material := StandardMaterial3D.new()
	nose_material.albedo_color = TSMTheme.ACCENT
	nose_mesh.material = nose_material
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.3, -0.45)
	_model.add_child(nose)

	var nameplate := Label3D.new()
	_nameplate = nameplate
	nameplate.text = "%s\n%s  Lv %d" % [
			str(Session.character.get("name", "?")),
			str(Session.character.get("class_id", "?")).capitalize(),
			int(Session.character.get("level", 1))]
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font_size = 48
	nameplate.pixel_size = 0.005
	nameplate.outline_size = 10
	nameplate.modulate = TSMTheme.ACCENT
	nameplate.position = Vector3(0, 2.5, 0)
	add_child(nameplate)


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.5, 0)
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, _distance)
	_pivot.add_child(_camera)
	_camera.current = true


static func _ensure_input_actions() -> void:
	for action in ACTION_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTION_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
