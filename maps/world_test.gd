extends Node3D
## Test world (M4): a big checkered field with some obstacles. Walk around with
## WASD / the touch joystick and turn the camera with the right mouse button or
## by dragging the right side of the screen. Combat and enemies come later.

const WORLD_SIZE := 200.0
const OBSTACLE_COUNT := 36

var player: PlayerController
var controls: TouchControls

var _info: Label


func _ready() -> void:
	# Opened without a loaded character (for example by pressing F6 on this
	# scene directly): go through the normal login flow instead.
	if not Session.has_character():
		FlowRouter.go_to_auth(get_tree())
		return
	_build_environment()
	_build_ground()
	_scatter_obstacles()
	_spawn_player()
	_build_hud()


## Adds a solid box to the world (used for obstacles and by tests).
func add_box(center: Vector3, size: Vector3, color: Color = Color("3a2a58")) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh_instance.mesh = box
	body.add_child(mesh_instance)
	add_child(body)
	return body


# ---------- world ----------

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = TSMTheme.BG
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("7a6a9a")
	environment.ambient_light_energy = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = false    # keep it light for phones
	add_child(sun)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(WORLD_SIZE, 1.0, WORLD_SIZE)
	shape.shape = floor_shape
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _checker_texture()
	material.uv1_scale = Vector3(WORLD_SIZE / 4.0, WORLD_SIZE / 4.0, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	plane.material = material
	mesh_instance.mesh = plane
	ground.add_child(mesh_instance)
	add_child(ground)

	# Invisible walls so nobody walks off the edge.
	var half := WORLD_SIZE / 2.0
	var wall_height := 10.0
	add_wall(Vector3(0, wall_height / 2.0, -half), Vector3(WORLD_SIZE, wall_height, 1))
	add_wall(Vector3(0, wall_height / 2.0, half), Vector3(WORLD_SIZE, wall_height, 1))
	add_wall(Vector3(-half, wall_height / 2.0, 0), Vector3(1, wall_height, WORLD_SIZE))
	add_wall(Vector3(half, wall_height / 2.0, 0), Vector3(1, wall_height, WORLD_SIZE))


func add_wall(center: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	wall.add_child(shape)
	add_child(wall)


func _scatter_obstacles() -> void:
	# The same seed gives the same field every time, so it feels like a place.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var limit := WORLD_SIZE / 2.0 - 10.0
	for i in OBSTACLE_COUNT:
		var pos := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		if pos.length() < 8.0:
			continue    # keep the spawn area clear
		var size := Vector3(rng.randf_range(1.5, 4.0), rng.randf_range(1.0, 6.0), rng.randf_range(1.5, 4.0))
		var tint := Color("3a2a58").lerp(Color("5b2a8c"), rng.randf())
		add_box(Vector3(pos.x, size.y / 2.0, pos.y), size, tint)


func _checker_texture() -> ImageTexture:
	var image := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dark := ((x >> 5) + (y >> 5)) % 2 == 0
			image.set_pixel(x, y, Color("221733") if dark else Color("2e2144"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# ---------- player and HUD ----------

func _spawn_player() -> void:
	controls = TouchControls.new()
	add_child(controls)

	player = PlayerController.new()
	player.controls = controls
	player.spawn_position = Vector3(0, 0.2, 0)
	add_child(player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2    # above the touch controls, so buttons get taps first
	add_child(layer)

	var hud := Control.new()
	hud.theme = TSMTheme.get_theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	_info = Label.new()
	_info.text = "%s  |  %s  |  Level %d  |  Speed %.2f" % [
			str(Session.character.get("name", "?")),
			str(Session.character.get("class_id", "?")).capitalize(),
			int(Session.character.get("level", 1)),
			player.move_speed()]
	_info.position = Vector2(24, 20)
	hud.add_child(_info)

	var sign_out := Button.new()
	sign_out.text = "Sign Out"
	sign_out.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sign_out.offset_left = -220
	sign_out.offset_right = -24
	sign_out.offset_top = 20
	sign_out.offset_bottom = 76
	sign_out.pressed.connect(_on_sign_out)
	hud.add_child(sign_out)

	var hint := Label.new()
	hint.text = "Move: WASD or left thumb  |  Look: right mouse button or drag the right side  |  Zoom: mouse wheel"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", TSMTheme.MUTED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -44
	hint.offset_right = 1300
	hint.offset_bottom = -12
	hud.add_child(hint)


func _on_sign_out() -> void:
	FirebaseService.sign_out()
	FlowRouter.go_to_auth(get_tree())
