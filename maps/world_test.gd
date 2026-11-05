extends Node3D
## Empty test world (M2.4). Shows the loaded character as a placeholder capsule.
## Movement, camera and combat arrive in later milestones.

var _model: MeshInstance3D


func _ready() -> void:
	# Opened without a loaded character (for example by pressing F6 on this
	# scene directly): go through the normal login flow instead.
	if not Session.has_character():
		FlowRouter.go_to_auth(get_tree())
		return
	_build_world()
	_build_hud()


func _process(delta: float) -> void:
	if _model != null:
		_model.rotate_y(delta * 0.6)


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = TSMTheme.BG
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("6a5a8a")
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = false    # keep it light for phones
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("1a1028")
	plane.material = ground_material
	ground.mesh = plane
	add_child(ground)

	_model = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("7a4bd1")
	capsule.material = body_material
	_model.mesh = capsule
	_model.position = Vector3(0, 0.9, 0)
	add_child(_model)

	var nameplate := Label3D.new()
	nameplate.text = "%s\n%s  Lv %d" % [
			str(Session.character.get("name", "?")),
			str(Session.character.get("class_id", "?")).capitalize(),
			int(Session.character.get("level", 1))]
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font_size = 48
	nameplate.pixel_size = 0.005
	nameplate.outline_size = 10
	nameplate.modulate = TSMTheme.ACCENT
	nameplate.position = Vector3(0, 2.4, 0)
	add_child(nameplate)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.8, 5.0)
	add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var hud := Control.new()
	hud.theme = TSMTheme.get_theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	var info := Label.new()
	info.text = "%s  |  %s  |  Level %d" % [
			str(Session.character.get("name", "?")),
			str(Session.character.get("class_id", "?")).capitalize(),
			int(Session.character.get("level", 1))]
	info.position = Vector2(24, 20)
	hud.add_child(info)

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
	hint.text = "Empty test world (M2.4). Movement arrives in M4."
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", TSMTheme.MUTED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -52
	hint.offset_right = 700
	hint.offset_bottom = -16
	hud.add_child(hint)


func _on_sign_out() -> void:
	FirebaseService.sign_out()
	FlowRouter.go_to_auth(get_tree())
