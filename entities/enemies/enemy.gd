class_name Enemy
extends CharacterBody3D
## One enemy, built from a row of the enemy sheet. The numbers are used exactly as
## they are in the sheet (health, attack, speeds, ranges, rewards). It never
## changes the enemy data.
##
## Behaviour: stands around and wanders near its home -> notices the player
## (or is hit) -> chases -> attacks -> gives up and walks home if the player gets
## too far -> heals when it is home. When it dies it gives EXP, gold and drops
## loot, if the player landed the killing blow.

signal killed(enemy: Enemy, rewards: Dictionary)

enum State { IDLE, ROAM, CHASE, ATTACK, RETURN, DEAD }

const GRAVITY := 14.0
const SIZE_BY_RARITY := {
	"common": 1.0, "uncommon": 1.05, "rare": 1.1, "epic": 1.2,
	"elite": 1.25, "legendary": 1.4, "mythic": 1.6,
}

## How many enemies are alive in the world right now (for the active cap).
static var active_count: int = 0
static var _bar_texture: ImageTexture

var enemy_id: String = ""
var home_position: Vector3 = Vector3.ZERO
## Where loot and floating numbers go (the world).
var world_root: Node
var combatant: Combatant
var state: State = State.IDLE
var target_radius: float = 0.6
## Tests only: fixed random numbers for this enemy's attacks and its loot.
var test_rolls: Dictionary = {}
var test_loot_rolls: Dictionary = {}

var _row: Dictionary = {}
var _ai: Dictionary = {}
var _player: PlayerController
var _aggro: bool = false
var _think_timer: float = 0.0
var _idle_timer: float = 2.0
var _attack_cooldown: float = 0.5
var _roam_target: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _body: Node3D
var _shape: CollisionShape3D
var _nameplate: Label3D
var _bar_back: Sprite3D
var _bar_fill: Sprite3D


## Call before adding the enemy to the tree.
func setup(id: String, home: Vector3, root: Node) -> void:
	enemy_id = id
	home_position = home
	world_root = root
	# Placed before it enters the world, so it never overlaps anything at the origin.
	position = home


func _ready() -> void:
	_row = DataRegistry.get_enemy(enemy_id)
	if _row.is_empty():
		push_error("[Enemy] unknown enemy id: %s" % enemy_id)
		queue_free()
		return
	_ai = DataRegistry.get_config("combat_rules").get("ai", {})
	_rng.randomize()
	add_to_group("targetable")
	active_count += 1

	_build_body()
	combatant = Combatant.new()
	add_child(combatant)
	combatant.setup(str(_row.get("enemy_name", enemy_id)), int(float(_row.get("enemy_level", 1))),
			EnemyStats.from_row(_row), "enemy")
	combatant.owner_node = self
	combatant.element_profile = ElementalSystem.profile_for_enemy(enemy_id)
	combatant.attack_profile = _build_attack_profile()
	combatant.damaged.connect(_on_damaged)
	combatant.changed.connect(_update_bar)
	combatant.died.connect(_on_died)
	_update_bar()

	global_position = home_position
	_idle_timer = _rng.randf_range(float(_ai.get("idle_min", 2.0)), float(_ai.get("idle_max", 5.0)))


func _exit_tree() -> void:
	active_count = maxi(0, active_count - 1)


## True while the enemy is fighting (it should not be removed then).
func is_engaged() -> bool:
	return state == State.CHASE or state == State.ATTACK


func is_dead() -> bool:
	return state == State.DEAD


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = float(_ai.get("think_interval", 0.2))
		_think()
	_act(delta)
	velocity.y -= GRAVITY * delta
	move_and_slide()


# ---------- deciding ----------

func _think() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as PlayerController
	var player_alive := _player != null and not _player.combatant.is_dead
	var to_player := _ground_distance(_player.global_position) if _player != null else INF
	var player_from_home := Vector2(_player.global_position.x - home_position.x,
			_player.global_position.z - home_position.z).length() if _player != null else INF
	var leash := float(_ai.get("leash_distance", 32.0))
	var from_home := _ground_distance(home_position)

	match state:
		State.IDLE, State.ROAM:
			var noticed: bool = to_player <= float(_ai.get("aggro_radius", 9.0)) and player_from_home <= leash
			if player_alive and (noticed or _aggro) and player_from_home <= leash:
				state = State.CHASE
		State.CHASE:
			if not player_alive or from_home > leash or player_from_home > leash:
				_begin_return()
			elif to_player <= _reach():
				state = State.ATTACK
		State.ATTACK:
			if not player_alive or from_home > leash or player_from_home > leash:
				_begin_return()
			elif to_player > _reach() + float(_ai.get("attack_range_padding", 0.3)):
				state = State.CHASE
		State.RETURN:
			if from_home <= 1.0:
				_arrive_home()


func _begin_return() -> void:
	state = State.RETURN
	_aggro = false


func _arrive_home() -> void:
	state = State.IDLE
	_aggro = false
	combatant.status.clear()
	combatant.heal(combatant.max_health())
	_idle_timer = _rng.randf_range(float(_ai.get("idle_min", 2.0)), float(_ai.get("idle_max", 5.0)))


# ---------- acting ----------

func _act(delta: float) -> void:
	match state:
		State.IDLE:
			_stop()
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				var roam := float(_row.get("roam_radius", 8.0))
				var angle := _rng.randf() * TAU
				var distance := sqrt(_rng.randf()) * roam
				_roam_target = home_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
				state = State.ROAM
		State.ROAM:
			if _ground_distance(_roam_target) < 0.6:
				state = State.IDLE
				_idle_timer = _rng.randf_range(float(_ai.get("idle_min", 2.0)), float(_ai.get("idle_max", 5.0)))
			else:
				_walk_toward(_roam_target, _walk_speed())
		State.CHASE:
			if _player != null:
				_walk_toward(_player.global_position, _run_speed())
		State.ATTACK:
			_stop()
			if _player != null:
				_face(_player.global_position)
				if _attack_cooldown <= 0.0:
					_do_attack()
		State.RETURN:
			_walk_toward(home_position, _run_speed())


func _do_attack() -> void:
	if _player == null or _player.combatant.is_dead or not combatant.status.can_attack():
		return
	CombatResolver.attack(combatant, _player.combatant, 1.0, test_rolls)
	_attack_cooldown = maxf(0.2, float(_row.get("atk_CD", 1.5)))
	if _body != null:
		_body.scale = _body.scale * 1.12
		create_tween().tween_property(_body, "scale", Vector3.ONE * _size(), 0.15)


func _walk_speed() -> float:
	return float(combatant.stats.get("move_speed", 2.0))


## Chase speed follows the move_speed stat, so Slow and Haste affect it too.
func _run_speed() -> float:
	var base := float(_row.get("move_speed", 0.0))
	var chase := float(_row.get("chase_speed", base))
	if base <= 0.0:
		return chase
	return chase * float(combatant.stats.get("move_speed", base)) / base


func _walk_toward(point: Vector3, speed: float) -> void:
	if not combatant.status.can_move():
		_stop()
		return
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() < 0.05:
		_stop()
		return
	var direction := flat.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face(point)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(point: Vector3) -> void:
	var toward := point - global_position
	if Vector2(toward.x, toward.z).length() > 0.01 and _body != null:
		_body.rotation.y = atan2(-toward.x, -toward.z)


func _reach() -> float:
	return float(_row.get("atk_RNG", 2.0)) + 0.4     # 0.4 = the player's body radius


func _ground_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


# ---------- being hit and dying ----------

func _on_damaged(result: Dictionary) -> void:
	if state == State.DEAD:
		return
	FloatingText.show_result(world_root if world_root != null else get_parent(),
			global_position + Vector3(0, 2.3 * _size(), 0), result)
	# Hitting an enemy makes it fight back.
	var attacker := combatant.last_attacker
	if attacker != null and attacker.team == "player" and state != State.ATTACK:
		_aggro = true
		if state != State.CHASE:
			state = State.CHASE
	if _body != null and result.get("outcome", "") == "hit":
		_body.scale = Vector3(1.1, 0.94, 1.1) * _size()
		create_tween().tween_property(_body, "scale", Vector3.ONE * _size(), 0.12)


func _on_died() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	remove_from_group("targetable")
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if _nameplate != null:
		_nameplate.visible = false
	if _bar_back != null:
		_bar_back.visible = false
		_bar_fill.visible = false

	var killer := combatant.last_attacker
	var by_player := killer != null and killer.team == "player"
	var rewards := LootTable.roll(enemy_id, test_loot_rolls)
	rewards["by_player"] = by_player

	if by_player:
		var exp_amount := ExpRules.exp_for_kill(int(rewards["exp"]), ExpRules.current_party_size())
		rewards["exp"] = exp_amount
		Session.grant_rewards(exp_amount, int(rewards["gold"]))
		var items: Array = rewards["items"]
		var drop_parent: Node = world_root if world_root != null else get_parent()
		for i in items.size():
			LootDrop.spawn(drop_parent, global_position, str(items[i]["item_id"]), int(items[i]["qty"]), i, items.size())
	else:
		rewards["exp"] = 0
		rewards["gold"] = 0
		rewards["items"] = []

	killed.emit(self, rewards)

	if _body != null:
		var fall := create_tween()
		fall.tween_property(_body, "rotation:x", -PI / 2.0, 0.5)
		fall.tween_interval(float(_ai.get("corpse_seconds", 3.0)))
		fall.tween_callback(queue_free)
	else:
		queue_free()


# ---------- how it looks ----------

func _size() -> float:
	return float(SIZE_BY_RARITY.get(str(_row.get("enemy_rarity", "common")).to_lower(), 1.0))


func _build_attack_profile() -> Dictionary:
	var effects: Array = []
	for token in str(_row.get("status_EFF", "")).split(","):
		var cleaned := token.strip_edges()
		if cleaned != "" and cleaned != "N/A" and StatusEffectManager.resolve_id(cleaned) != "":
			effects.append(cleaned)
	if effects.is_empty():
		return {}
	return {"on_hit": {"effects": effects, "chance": CombatProfile.to_fraction(float(_row.get("effect_chance", 0.0)))}}


func _build_body() -> void:
	var scale_factor := _size()
	var color := TSMTheme.rarity_color(str(_row.get("enemy_rarity", "common")))

	_shape = CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45 * scale_factor
	capsule_shape.height = 1.6 * scale_factor
	_shape.shape = capsule_shape
	_shape.position = Vector3(0, 0.8 * scale_factor, 0)
	add_child(_shape)

	_body = Node3D.new()
	_body.scale = Vector3.ONE * scale_factor
	add_child(_body)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.6
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.35)
	capsule.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.8, 0)
	_body.add_child(mesh)

	# Two "eyes" show which way it is facing (forward is -Z).
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color("ff3b3b")
	eye_material.emission_enabled = true
	eye_material.emission = Color("ff3b3b")
	for side in [-0.16, 0.16]:
		var eye := MeshInstance3D.new()
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.12, 0.08, 0.08)
		eye_mesh.material = eye_material
		eye.mesh = eye_mesh
		eye.position = Vector3(side, 1.2, -0.42)
		_body.add_child(eye)

	_nameplate = Label3D.new()
	_nameplate.text = "%s  Lv %d" % [str(_row.get("enemy_name", enemy_id)), int(float(_row.get("enemy_level", 1)))]
	_nameplate.modulate = color
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.font_size = 36
	_nameplate.pixel_size = 0.005
	_nameplate.outline_size = 8
	_nameplate.position = Vector3(0, 2.25 * scale_factor, 0)
	add_child(_nameplate)

	var bar_y := 2.0 * scale_factor
	_bar_back = _make_bar_sprite(Color(0.05, 0.03, 0.08, 0.9), 0)
	_bar_back.position = Vector3(0, bar_y, 0)
	add_child(_bar_back)
	_bar_fill = _make_bar_sprite(Color("d04040"), 1)
	_bar_fill.position = Vector3(0, bar_y, 0)
	add_child(_bar_fill)


func _make_bar_sprite(color: Color, priority: int) -> Sprite3D:
	if _bar_texture == null:
		var image := Image.create(64, 6, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_bar_texture = ImageTexture.create_from_image(image)
	var sprite := Sprite3D.new()
	sprite.texture = _bar_texture
	sprite.centered = false
	sprite.offset = Vector2(-32, -3)
	sprite.pixel_size = 0.02
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.modulate = color
	sprite.render_priority = priority
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 64, 6)
	return sprite


func _update_bar() -> void:
	if _bar_fill == null or combatant == null:
		return
	var share := clampf(float(combatant.hp) / maxf(1.0, float(combatant.max_health())), 0.0, 1.0)
	_bar_fill.region_rect = Rect2(0, 0, maxf(0.01, 64.0 * share), 6)
