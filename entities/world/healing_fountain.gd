class_name HealingFountain
extends Node3D
## A magic fountain. Standing near it restores health, 10 per second by default
## (set in TSM_Maps.json), with a cool glow and rising sparkles.

var fountain_id: String = ""
var heal_per_second: float = 10.0
var radius: float = 3.6
var healing_now: bool = false

var _pool: float = 0.0
var _shown: int = 0
var _shown_timer: float = 0.0
var _sparkles: CPUParticles3D
var _light: OmniLight3D
var _time: float = 0.0


func _ready() -> void:
	add_to_group("fountain")
	var map := MapData.get_map(str(Session.character.get("current_map", "map_1")))
	heal_per_second = float(map.get("heal_per_second", 10))
	radius = float(map.get("fountain_radius", 3.6))

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("5a566a")
	var basin := MeshInstance3D.new()
	var basin_mesh := CylinderMesh.new()
	basin_mesh.top_radius = 1.7
	basin_mesh.bottom_radius = 1.9
	basin_mesh.height = 0.6
	basin_mesh.radial_segments = 16
	basin_mesh.material = stone
	basin.mesh = basin_mesh
	basin.position = Vector3(0, 0.3, 0)
	add_child(basin)

	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.35, 0.85, 1.0, 0.8)
	glow.emission_enabled = true
	glow.emission = Color("4fd7ff")
	glow.emission_energy_multiplier = 1.4
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 1.5
	water_mesh.bottom_radius = 1.5
	water_mesh.height = 0.05
	water_mesh.radial_segments = 16
	water_mesh.material = glow
	water.mesh = water_mesh
	water.position = Vector3(0, 0.62, 0)
	add_child(water)

	var column := MeshInstance3D.new()
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.18
	column_mesh.bottom_radius = 0.3
	column_mesh.height = 1.6
	column_mesh.material = stone
	column.mesh = column_mesh
	column.position = Vector3(0, 1.3, 0)
	add_child(column)

	_sparkles = CPUParticles3D.new()
	_sparkles.amount = 28
	_sparkles.lifetime = 1.8
	_sparkles.direction = Vector3.UP
	_sparkles.spread = 28.0
	_sparkles.initial_velocity_min = 1.0
	_sparkles.initial_velocity_max = 2.2
	_sparkles.gravity = Vector3(0, -1.6, 0)
	_sparkles.color = Color("8fe8ff")
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.05
	spark_mesh.height = 0.1
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color("aef0ff")
	spark_mesh.material = spark_material
	_sparkles.mesh = spark_mesh
	_sparkles.position = Vector3(0, 2.1, 0)
	add_child(_sparkles)

	_light = OmniLight3D.new()
	_light.light_color = Color("4fd7ff")
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.6, 0)
	add_child(_light)

	var label := Label3D.new()
	label.text = "Healing Fountain"
	label.modulate = Color("8fe8ff")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.005
	label.outline_size = 8
	label.position = Vector3(0, 3.4, 0)
	add_child(label)


func _physics_process(delta: float) -> void:
	_time += delta
	_light.light_energy = 1.0 + sin(_time * 2.0) * 0.2

	var player := get_tree().get_first_node_in_group("player") as PlayerController
	healing_now = false
	if player != null and not player.is_dead() and player.combatant != null:
		var distance := Vector2(player.global_position.x - global_position.x,
				player.global_position.z - global_position.z).length()
		if distance <= radius and player.combatant.hp < player.combatant.max_health():
			healing_now = true
			_pool += heal_per_second * delta
			var whole := int(_pool)
			if whole > 0:
				_pool -= whole
				_shown += player.combatant.restore("health", whole)
	_sparkles.speed_scale = 2.0 if healing_now else 1.0

	# One green number a second, so it does not flood the screen.
	_shown_timer += delta
	if _shown_timer >= 1.0:
		_shown_timer = 0.0
		if _shown > 0 and player != null:
			FloatingText.spawn(get_parent(), player.global_position + Vector3(0, 2.6, 0),
					"+%d" % _shown, Color("7be0ff"), 1.0)
		_shown = 0
