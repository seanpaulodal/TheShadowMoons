class_name Summon
extends Node3D
## A helper called by a skill (a turret, a skeleton, a bone archer...). It follows
## its owner, picks the nearest enemy and attacks it until its time runs out.
## Its hits count as the owner's: kills give the owner EXP and loot. For now
## summons cannot be hurt. What each one is like is in TSM_Summons.json.

var summon_id: String = ""
var definition: Dictionary = {}
var owner_player: PlayerController
var attack_damage: float = 0.0           # raw damage per attack (before the enemy's defense)
var remaining: float = 30.0

var _cooldown: float = 0.5
var _retarget: float = 0.0
var _target: Variant = null
var _body: MeshInstance3D
var _pulse: float = 0.0


func setup(id: String, owner_node: PlayerController, seconds: float, damage_per_attack: float, at: Vector3) -> void:
	summon_id = id
	definition = DataRegistry.get_config("summons").get("summons", {}).get(id, {})
	owner_player = owner_node
	remaining = seconds
	attack_damage = damage_per_attack
	position = Vector3(at.x, 0.0, at.z)          # placed before it enters the world


func kind() -> String:
	return str(definition.get("kind", "melee"))


func display_name() -> String:
	return str(definition.get("name", summon_id))


func _ready() -> void:
	add_to_group("summon")
	var size := float(definition.get("size", 1.0))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(str(definition.get("color", "ffffff")))
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.35
	_body = MeshInstance3D.new()
	if kind() == "turret" or kind() == "construct":
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.8, 0.8) * size
		box.material = material
		_body.mesh = box
		_body.position = Vector3(0, 0.4 * size, 0)
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.32 * size
		capsule.height = 1.5 * size
		capsule.material = material
		_body.mesh = capsule
		_body.position = Vector3(0, 0.75 * size, 0)
	add_child(_body)

	var label := Label3D.new()
	label.text = display_name()
	label.modulate = Color(str(definition.get("color", "ffffff"))).lightened(0.4)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.pixel_size = 0.005
	label.outline_size = 6
	label.position = Vector3(0, 1.9 * size, 0)
	add_child(label)


func _physics_process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0.0 or owner_player == null or not is_instance_valid(owner_player) or owner_player.is_dead():
		_expire()
		return
	_cooldown -= delta
	_retarget -= delta
	if _pulse > 0.0:
		_pulse -= delta
		_body.scale = Vector3.ONE * (1.0 + maxf(0.0, _pulse) * 0.6)

	if _retarget <= 0.0 or not Targeting.is_valid_target(_target):
		_retarget = 0.3
		_target = _find_target()

	var speed := float(definition.get("move_speed", 0.0))
	var follow: Dictionary = DataRegistry.get_config("summons").get("follow", {})
	if Targeting.is_valid_target(_target):
		var distance := Targeting.distance(self, _target)
		var reach := float(definition.get("attack_range", 2.0))
		_face((_target as Node3D).global_position)
		if distance <= reach:
			if _cooldown <= 0.0:
				_attack(_target)
				_cooldown = float(definition.get("attack_interval", 1.0))
		elif speed > 0.0:
			_step_toward((_target as Node3D).global_position, speed * delta)
	elif speed > 0.0:
		var home := owner_player.global_position
		var away := Vector2(home.x - global_position.x, home.z - global_position.z).length()
		if away > float(follow.get("teleport_distance", 25.0)):
			global_position = Vector3(home.x + 1.5, 0.0, home.z + 1.5)
		elif away > float(follow.get("catch_up_distance", 5.0)):
			_step_toward(home, speed * delta)


## The nearest enemy within the follow radius of the owner (or of the summon).
func _find_target() -> Variant:
	var radius := float(DataRegistry.get_config("summons").get("follow", {}).get("aggro_radius", 12.0))
	var best: Variant = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("targetable"):
		if not (node is Node3D) or not Targeting.is_valid_target(node):
			continue
		if not (node as Node3D).has_method("is_dead") and not (node is Enemy):
			continue                                   # practice dummies are not worth chasing
		var from_owner := Targeting.distance(owner_player, node)
		var from_me := Targeting.distance(self, node)
		if minf(from_owner, from_me) <= radius and from_me < best_distance:
			best = node
			best_distance = from_me
	return best


func _face(point: Vector3) -> void:
	var toward := point - global_position
	if Vector2(toward.x, toward.z).length() > 0.01:
		rotation.y = atan2(-toward.x, -toward.z)


func _step_toward(point: Vector3, distance: float) -> void:
	var toward := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if toward.length() > 0.01:
		global_position += toward.normalized() * minf(distance, toward.length())


func _attack(enemy: Node3D) -> void:
	var fighter: Combatant = enemy.get("combatant")
	var bonus := owner_player.skills.summon_attack_bonus()
	var params := {"raw": attack_damage * (1.0 + bonus), "damage_type": str(definition.get("damage_type", "physical")),
			"crit_bonus": 0.0, "power_multiplier": 1.0}
	var result := CombatResolver.skill_hit(owner_player.combatant, fighter, params, {})
	_pulse = 0.2
	if result["ok"]:
		owner_player.on_summon_hit(result, enemy)
		if ["turret", "ranged", "caster", "construct"].has(kind()):
			_shoot(enemy.global_position + Vector3(0, 1.0, 0))


## A small glowing shot flying to the target (looks only).
func _shoot(to: Vector3) -> void:
	var shot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 6
	sphere.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(str(definition.get("color", "ffffff"))).lightened(0.5)
	sphere.material = material
	shot.mesh = sphere
	get_parent().add_child(shot)
	shot.global_position = global_position + Vector3(0, 1.0, 0)
	var tween := shot.create_tween()
	tween.tween_property(shot, "global_position", to, 0.15)
	tween.tween_callback(shot.queue_free)


## Time is up: a bomb-type summon goes off, then it disappears.
func _expire() -> void:
	if remaining <= 0.0 and float(definition.get("explode_on_expire_percent", 0.0)) > 0.0 \
			and owner_player != null and is_instance_valid(owner_player) and not owner_player.is_dead():
		var radius := float(definition.get("explode_radius", 4.0))
		for node in get_tree().get_nodes_in_group("targetable"):
			if node is Node3D and Targeting.is_valid_target(node) and Targeting.distance(self, node) <= radius:
				var fighter: Combatant = node.get("combatant")
				var params := {"raw": attack_damage * float(definition["explode_on_expire_percent"]),
						"damage_type": str(definition.get("damage_type", "dark")), "crit_bonus": 0.0, "power_multiplier": 1.0}
				var result := CombatResolver.skill_hit(owner_player.combatant, fighter, params, {})
				if result["ok"]:
					owner_player.on_summon_hit(result, node)
	remove_from_group("summon")
	queue_free()
