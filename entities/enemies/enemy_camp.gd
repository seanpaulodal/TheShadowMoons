class_name EnemyCamp
extends Node3D
## A spot in the world that keeps a few enemies of one kind. To save the phone's
## power, a camp far from the player has NO enemies at all: they appear when the
## player gets near and disappear again when the player goes far away (unless they
## are fighting). Killed enemies come back after a while.

var enemy_id: String = ""
var count: int = 3
var radius: float = 8.0
var respawn_seconds: float = 30.0
var wake_distance: float = 70.0
var world_root: Node

var _slots: Array = []        # [{"home": Vector3, "enemy": Enemy or null, "respawn_in": float}]
var _awake: bool = false
var _check_timer: float = 0.0


## Call before adding the camp to the tree. `position_xz` is [x, z].
func setup(def: Dictionary, rules: Dictionary, root: Node) -> void:
	enemy_id = str(def["enemy_id"])
	count = int(def.get("count", 3))
	radius = float(def.get("radius", 8.0))
	var at: Array = def.get("position", [0, 0])
	position = Vector3(float(at[0]), 0.0, float(at[1]))
	respawn_seconds = float(rules.get("respawn_seconds", 30.0))
	wake_distance = float(rules.get("wake_distance", 70.0))
	world_root = root


func _ready() -> void:
	# The same camp always gets the same spots, so the world feels like a place.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([enemy_id, position.x, position.z])
	for i in count:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * radius
		_slots.append({
			"home": position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance),
			"enemy": null,
			"respawn_in": 0.0,
		})


func is_awake() -> bool:
	return _awake


## How many of this camp's enemies are alive right now.
func alive_count() -> int:
	var total := 0
	for slot in _slots:
		var enemy = slot["enemy"]
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
			total += 1
	return total


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= 0.5:
		tick(_check_timer)
		_check_timer = 0.0


## Moves the camp's clock forward (tests call this directly).
func tick(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var distance := Vector2(player.global_position.x - global_position.x,
			player.global_position.z - global_position.z).length()
	# A little margin so the camp does not flicker at the edge.
	_awake = distance <= (wake_distance * 1.15 if _awake else wake_distance)

	var cap := int(DataRegistry.get_config("world_camps").get("map_1", {}).get("max_active_enemies", 25))
	for slot in _slots:
		var enemy = slot["enemy"]
		if enemy != null and not is_instance_valid(enemy):
			slot["enemy"] = null
			enemy = null

		if _awake:
			if enemy == null:
				slot["respawn_in"] = maxf(0.0, float(slot["respawn_in"]) - delta)
				if float(slot["respawn_in"]) <= 0.0 and Enemy.active_count < cap:
					slot["enemy"] = _spawn(slot["home"])
		elif enemy != null and not enemy.is_engaged() and not enemy.is_dead():
			enemy.queue_free()
			slot["enemy"] = null
			slot["respawn_in"] = 0.0


func _spawn(home: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.setup(enemy_id, home, world_root)
	enemy.killed.connect(_on_enemy_killed)
	world_root.add_child(enemy)
	return enemy


func _on_enemy_killed(dead: Enemy, _rewards: Dictionary) -> void:
	for slot in _slots:
		if slot["enemy"] == dead:
			slot["respawn_in"] = respawn_seconds
			# The corpse stays for a few seconds, then it is removed by the enemy itself.
			slot["enemy"] = null
