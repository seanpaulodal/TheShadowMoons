class_name Waypoint
extends StaticBody3D
## A teleport obelisk. It glows RED until you activate it and BLUE afterwards.
## To activate: walk up to it, with no living enemy nearby, and tap Activate.
## Active waypoints can be teleported to from the Map window.

var waypoint_id: String = ""
var display_name: String = ""
var level_range: Array = [1, 1]
var unlocked: bool = false

var _crystal: MeshInstance3D
var _crystal_material: StandardMaterial3D
var _light: OmniLight3D
var _label: Label3D
var _time: float = 0.0


## The closest waypoint within `radius` of `from`, or null.
static func nearest(from: Node3D, radius: float) -> Waypoint:
	var best: Waypoint = null
	var best_distance := INF
	for node in from.get_tree().get_nodes_in_group("waypoint"):
		var waypoint := node as Waypoint
		if waypoint == null:
			continue
		var distance := waypoint.ground_distance(from.global_position)
		if distance <= radius and distance < best_distance:
			best = waypoint
			best_distance = distance
	return best


func _ready() -> void:
	add_to_group("waypoint")
	var entry := MapData.waypoint(str(Session.character.get("current_map", "map_1")), waypoint_id)
	display_name = str(entry.get("name", waypoint_id))
	level_range = entry.get("level_range", [1, 1])

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.9
	cylinder.height = 2.8
	shape.shape = cylinder
	shape.position = Vector3(0, 1.4, 0)
	add_child(shape)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("3b3548")
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.1
	base_mesh.bottom_radius = 1.3
	base_mesh.height = 0.35
	base_mesh.radial_segments = 12
	base_mesh.material = stone
	base.mesh = base_mesh
	base.position = Vector3(0, 0.17, 0)
	add_child(base)

	var pillar := MeshInstance3D.new()
	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(0.8, 2.4, 0.8)
	pillar_mesh.material = stone
	pillar.mesh = pillar_mesh
	pillar.position = Vector3(0, 1.4, 0)
	add_child(pillar)

	_crystal_material = StandardMaterial3D.new()
	_crystal_material.emission_enabled = true
	_crystal_material.emission_energy_multiplier = 1.6
	_crystal = MeshInstance3D.new()
	var crystal_mesh := PrismMesh.new()
	crystal_mesh.size = Vector3(0.7, 1.0, 0.7)
	crystal_mesh.material = _crystal_material
	_crystal.mesh = crystal_mesh
	_crystal.position = Vector3(0, 3.2, 0)
	add_child(_crystal)

	_light = OmniLight3D.new()
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 3.0, 0)
	add_child(_light)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.005
	_label.outline_size = 8
	_label.position = Vector3(0, 4.3, 0)
	add_child(_label)

	Session.character_changed.connect(refresh_state)
	refresh_state()


## Reads whether the player has activated this waypoint, and recolours it.
func refresh_state() -> void:
	unlocked = WaypointRules.is_unlocked(Session.character, waypoint_id)
	var color := Color("4aa8ff") if unlocked else Color("ff4a4a")
	_crystal_material.albedo_color = color
	_crystal_material.emission = color
	_light.light_color = color
	_label.text = display_name if unlocked else "%s  (inactive)" % display_name
	_label.modulate = color.lightened(0.35)


func is_blue() -> bool:
	return unlocked


func ground_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


## Living enemies within `radius` of the waypoint (a waypoint can only be
## activated once the area around it is clear).
func enemies_near(radius: float) -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group("targetable"):
		if node is Enemy and not (node as Enemy).is_dead() and ground_distance((node as Node3D).global_position) <= radius:
			total += 1
	return total


func _process(delta: float) -> void:
	_time += delta
	if _crystal != null:
		_crystal.rotation.y = _time * 1.2
		_crystal.position.y = 3.2 + sin(_time * 2.0) * 0.12
		_light.light_energy = 1.1 + sin(_time * 2.5) * 0.25
