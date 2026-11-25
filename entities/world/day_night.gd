class_name DayNight
extends Node
## Runs the sky: a real-time 24 hour cycle. It turns the sun, the ambient light,
## the sky colour and the fog with the time of day (see DayNightRules), and
## shows the three moons at night. The moons are fixed in the sky of this map
## (their places are in TSM_Maps.json) and follow the camera, so they never move
## closer as you walk.

const MOON_DISTANCE := 380.0

## Tests only: a fixed hour (0..24). Negative means use the real clock.
var hour_override: float = -1.0

var _sun: DirectionalLight3D
var _environment: Environment
var _rules: Dictionary = {}
var _moons: Array = []          # [{"mesh": MeshInstance3D, "material": StandardMaterial3D, "direction": Vector3}]
var _timer: float = 0.0
var _last_state: Dictionary = {}


func setup(sun: DirectionalLight3D, environment: Environment, map_id: String) -> void:
	_sun = sun
	_environment = environment
	var map := MapData.get_map(map_id)
	_rules = map.get("day_night", {})
	add_to_group("day_night")

	_environment.fog_enabled = true
	_environment.fog_sky_affect = 1.0
	for entry in map.get("moons", []):
		_add_moon(entry)
	apply_now()


func current_hour() -> float:
	if hour_override >= 0.0:
		return hour_override
	return DayNightRules.hour_from_rules(_rules)


func last_state() -> Dictionary:
	return _last_state


func moon_count() -> int:
	return _moons.size()


func moon_visible(index: int) -> bool:
	return (_moons[index]["mesh"] as MeshInstance3D).visible


## Moves the sky to the current hour.
func apply_now() -> void:
	var hour := current_hour()
	var state := DayNightRules.state_for_hour(hour)
	_last_state = state

	var elevation := float(state["sun_elevation"])
	if float(state["sun_energy"]) > 0.02:
		_sun.rotation_degrees = Vector3(-clampf(elevation, 8.0, 80.0), float(state["sun_yaw"]), 0.0)
		_sun.light_energy = float(state["sun_energy"])
		_sun.light_color = state["sun_color"]
	else:
		# After sunset a faint blue moonlight comes from where the moons are.
		_sun.rotation_degrees = Vector3(-38.0, 205.0, 0.0)
		_sun.light_energy = 0.28 * float(state["night"])
		_sun.light_color = Color("8fa4ff")

	_environment.ambient_light_color = state["ambient_color"]
	_environment.ambient_light_energy = float(state["ambient_energy"])
	_environment.background_color = state["sky_color"]
	_environment.fog_light_color = state["fog_color"]
	_environment.fog_density = lerpf(0.0018, 0.006, float(state["night"]))

	var night := float(state["night"])
	for moon in _moons:
		var mesh: MeshInstance3D = moon["mesh"]
		mesh.visible = night > 0.05
		var material: StandardMaterial3D = moon["material"]
		var color := material.albedo_color
		color.a = clampf((night - 0.2) / 0.8, 0.0, 1.0)
		material.albedo_color = color


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		apply_now()
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		for moon in _moons:
			(moon["mesh"] as MeshInstance3D).global_position = camera.global_position + (moon["direction"] as Vector3) * MOON_DISTANCE


func _add_moon(entry: Dictionary) -> void:
	var azimuth := deg_to_rad(float(entry.get("azimuth", 200.0)))
	var elevation := deg_to_rad(float(entry.get("elevation", 30.0)))
	var direction := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation)).normalized()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(str(entry.get("color", "c9b8ff")))
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = float(entry.get("size", 20.0))
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.material = material
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_moons.append({"mesh": mesh, "material": material, "direction": direction})
