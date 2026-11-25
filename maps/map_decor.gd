class_name MapDecor
extends Node3D
## The scenery of a map: balete trees, rocks, a ring of tropical mountains and a
## ruined temple. Trees, rocks and mountains are drawn in groups (one draw call
## each), and all solid things share ONE physics body, so it stays light on a
## phone. Nothing is placed inside the "reserved" circles (the start, shops,
## camps, waypoints and fountains).

var tree_positions: Array = []        # Vector2 (x, z)
var rock_positions: Array = []
var mountain_count: int = 0

var _body: StaticBody3D


## map_id: which map. reserved: [[Vector2 centre, float radius], ...] kept clear.
func build(map_id: String, reserved: Array) -> void:
	var map := MapData.get_map(map_id)
	var decor: Dictionary = map.get("decor", {})
	var half := float(map.get("size", 200.0)) / 2.0 - 6.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(decor.get("seed", 1))

	_body = StaticBody3D.new()
	_body.name = "DecorBody"
	add_child(_body)

	var temple := _vec(decor.get("temple", [0, 0]))
	var keep_clear: Array = reserved.duplicate()
	keep_clear.append([temple, 11.0])

	tree_positions = _scatter(rng, int(decor.get("trees", 0)), half, 5.0, keep_clear)
	rock_positions = _scatter(rng, int(decor.get("rocks", 0)), half, 3.5, keep_clear + _as_reserved(tree_positions, 1.6))
	_build_trees(rng)
	_build_rocks(rng)
	_build_mountains(rng, int(decor.get("mountains", 0)), float(map.get("size", 200.0)))
	if temple != Vector2.ZERO:
		_build_temple(temple)


## Frees all scenery (tests use this to get a clear field).
func clear() -> void:
	for child in get_children():
		child.queue_free()
	tree_positions.clear()
	rock_positions.clear()


func _vec(at: Array) -> Vector2:
	return Vector2(float(at[0]), float(at[1]))


func _as_reserved(points: Array, radius: float) -> Array:
	var result: Array = []
	for point in points:
		result.append([point, radius])
	return result


## Random spots that are not inside a reserved circle and not too close to each other.
func _scatter(rng: RandomNumberGenerator, wanted: int, half: float, spacing: float, reserved: Array) -> Array:
	var spots: Array = []
	var attempts := 0
	while spots.size() < wanted and attempts < wanted * 30:
		attempts += 1
		var spot := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var allowed := true
		for zone in reserved:
			if spot.distance_to(zone[0]) < float(zone[1]):
				allowed = false
				break
		if allowed:
			for other in spots:
				if spot.distance_to(other) < spacing:
					allowed = false
					break
		if allowed:
			spots.append(spot)
	return spots


func _multimesh(mesh: Mesh, transforms: Array) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _build_trees(rng: RandomNumberGenerator) -> void:
	if tree_positions.is_empty():
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.32
	trunk_mesh.bottom_radius = 0.42
	trunk_mesh.height = 4.2
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _material(Color("3b2c24"))
	var root_mesh := CylinderMesh.new()          # the wide "aerial roots" of a balete
	root_mesh.top_radius = 0.4
	root_mesh.bottom_radius = 1.25
	root_mesh.height = 1.6
	root_mesh.radial_segments = 7
	root_mesh.material = _material(Color("33261f"))
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 2.7
	canopy_mesh.height = 3.6
	canopy_mesh.radial_segments = 8
	canopy_mesh.rings = 4
	canopy_mesh.material = _material(Color("1f4a3a"))

	var trunks: Array = []
	var roots: Array = []
	var canopies: Array = []
	for spot in tree_positions:
		var size := rng.randf_range(0.85, 1.45)
		var turn := rng.randf() * TAU
		var basis := Basis(Vector3.UP, turn).scaled(Vector3(size, size, size))
		trunks.append(Transform3D(basis, Vector3(spot.x, 2.1 * size, spot.y)))
		roots.append(Transform3D(basis, Vector3(spot.x, 0.8 * size, spot.y)))
		canopies.append(Transform3D(basis.scaled(Vector3(1.0, 0.8, 1.0)), Vector3(spot.x, 5.6 * size, spot.y)))
		_add_cylinder_shape(Vector3(spot.x, 2.0 * size, spot.y), 0.8 * size, 4.0 * size)
	_multimesh(trunk_mesh, trunks)
	_multimesh(root_mesh, roots)
	_multimesh(canopy_mesh, canopies)


func _build_rocks(rng: RandomNumberGenerator) -> void:
	if rock_positions.is_empty():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	mesh.material = _material(Color("4a4658"))
	var transforms: Array = []
	for spot in rock_positions:
		var width := rng.randf_range(0.9, 2.2)
		var height := rng.randf_range(0.6, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, height, width))
		transforms.append(Transform3D(basis, Vector3(spot.x, height * 0.55, spot.y)))
		_add_cylinder_shape(Vector3(spot.x, height * 0.6, spot.y), width * 0.9, height * 1.2)
	_multimesh(mesh, transforms)


func _build_mountains(rng: RandomNumberGenerator, wanted: int, map_size: float) -> void:
	mountain_count = wanted
	if wanted <= 0:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 34.0
	mesh.height = 70.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = _material(Color("2c4a40"))
	var transforms: Array = []
	for i in wanted:
		var angle := TAU * float(i) / float(wanted) + rng.randf_range(-0.12, 0.12)
		var distance := map_size * 0.5 + rng.randf_range(55.0, 90.0)
		var size := rng.randf_range(0.8, 1.5)
		var tall := rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, tall, size))
		transforms.append(Transform3D(basis, Vector3(cos(angle) * distance, 35.0 * tall, sin(angle) * distance)))
	_multimesh(mesh, transforms)


## A broken temple: a stone floor, a ring of pillars (some fallen) and an altar.
func _build_temple(centre: Vector2) -> void:
	var stone := _material(Color("5d5870"))
	var dark := _material(Color("46415a"))

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(15, 0.3, 15)
	floor_mesh.material = dark
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(centre.x, 0.15, centre.y)
	add_child(floor_instance)

	var altar_mesh := BoxMesh.new()
	altar_mesh.size = Vector3(2.4, 1.1, 1.4)
	altar_mesh.material = stone
	var altar := MeshInstance3D.new()
	altar.mesh = altar_mesh
	altar.position = Vector3(centre.x, 0.85, centre.y)
	add_child(altar)
	_add_cylinder_shape(Vector3(centre.x, 0.9, centre.y), 1.3, 1.8)

	for i in 8:
		var angle := TAU * float(i) / 8.0
		var spot := centre + Vector2(cos(angle), sin(angle)) * 6.0
		var broken := i % 3 == 0
		var pillar_mesh := CylinderMesh.new()
		pillar_mesh.top_radius = 0.5
		pillar_mesh.bottom_radius = 0.6
		pillar_mesh.height = 1.8 if broken else 4.6
		pillar_mesh.radial_segments = 8
		pillar_mesh.material = stone
		var pillar := MeshInstance3D.new()
		pillar.mesh = pillar_mesh
		pillar.position = Vector3(spot.x, pillar_mesh.height * 0.5, spot.y)
		add_child(pillar)
		_add_cylinder_shape(Vector3(spot.x, pillar_mesh.height * 0.5, spot.y), 0.6, pillar_mesh.height)
		if broken:
			var block_mesh := BoxMesh.new()
			block_mesh.size = Vector3(1.2, 0.8, 1.2)
			block_mesh.material = stone
			var block := MeshInstance3D.new()
			block.mesh = block_mesh
			block.position = Vector3(spot.x + 1.4, 0.4, spot.y + 0.6)
			block.rotation = Vector3(0.0, angle, 0.3)
			add_child(block)


func _add_cylinder_shape(at: Vector3, radius: float, height: float) -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position = at
	_body.add_child(shape)
