class_name TrainingDummy
extends StaticBody3D
## A practice target. Its numbers come from the enemy data ("training_dummy":
## level 999999, health 999999, no attack, no rewards) and it never dies: when its
## health runs out it simply refills. It keeps a damage-per-second meter.

var combatant: Combatant
var dps_meter := DpsMeter.new()
var target_radius: float = 0.6

var _mesh_root: Node3D
var _nameplate: Label3D
var _refresh_timer: float = 0.0


func _ready() -> void:
	add_to_group("targetable")
	_build_body()

	var row := DataRegistry.get_enemy("training_dummy")
	combatant = Combatant.new()
	add_child(combatant)
	combatant.setup(str(row.get("enemy_name", "Training Dummy")),
			int(float(row.get("enemy_level", 1))), EnemyStats.from_row(row), "enemy")
	combatant.immortal = true
	combatant.element_profile = ElementalSystem.profile_for_enemy("training_dummy")
	combatant.damaged.connect(_on_damaged)
	_update_nameplate()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		_update_nameplate()


func _on_damaged(result: Dictionary) -> void:
	dps_meter.record(result)
	FloatingText.show_result(get_parent(), global_position + Vector3(0, 2.4, 0), result)
	if _mesh_root != null and result.get("outcome", "") == "hit":
		_mesh_root.scale = Vector3(1.08, 0.96, 1.08)
		create_tween().tween_property(_mesh_root, "scale", Vector3.ONE, 0.12)


func _update_nameplate() -> void:
	if _nameplate == null or combatant == null:
		return
	_nameplate.text = "%s\nDPS %d" % [combatant.display_name, roundi(dps_meter.dps())]


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = target_radius
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)

	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("7a5a3a")
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("b0453a")

	_add_part(Vector3(0, 0.08, 0), _cylinder_mesh(0.7, 0.16, wood))
	_add_part(Vector3(0, 1.0, 0), _cylinder_mesh(0.12, 2.0, wood))
	_add_part(Vector3(0, 1.5, 0), _box_mesh(Vector3(1.2, 0.14, 0.14), wood))
	_add_part(Vector3(0, 1.45, 0), _cylinder_mesh(0.34, 0.7, cloth))

	_nameplate = Label3D.new()
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.font_size = 40
	_nameplate.pixel_size = 0.005
	_nameplate.outline_size = 8
	_nameplate.modulate = Color("8fd0ff")
	_nameplate.position = Vector3(0, 2.9, 0)
	add_child(_nameplate)


func _add_part(position_in_parent: Vector3, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position_in_parent
	_mesh_root.add_child(instance)


func _cylinder_mesh(radius: float, height: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	return mesh


func _box_mesh(size: Vector3, material: Material) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh
