extends Node3D
## Map 1 (Oakhaven Wilds): balete trees, rocks, a ruined temple, mountains in the
## distance, a village market, waypoints, healing fountains, enemy camps and a
## day and night sky. Everything placed in it comes from the data files.

const WORLD_SIZE := 200.0
const MAP_ID := "map_1"

var player: PlayerController
var controls: TouchControls
var combat_hud: CombatHud
var camps: Array = []
var shop_npcs: Array = []
var waypoints: Array = []
var fountains: Array = []
var decor: MapDecor
var day_night: DayNight

var _sun: DirectionalLight3D
var _environment: Environment



func _ready() -> void:
	# Opened without a loaded character (for example by pressing F6 on this
	# scene directly): go through the normal login flow instead.
	if not Session.has_character():
		FlowRouter.go_to_auth(get_tree())
		return
	_build_environment()
	_build_ground()
	_spawn_shops()
	_spawn_waypoints()
	_spawn_fountains()
	_build_decor()
	_spawn_player()
	add_dummy(Vector3(0, 0, -6))
	add_dummy(Vector3(-6, 0, -10))
	_spawn_camps()
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


## Places the shopkeepers listed in TSM_Shop_Rules.json.
func _spawn_shops() -> void:
	for def in DataRegistry.get_config("shop_rules").get("shops", []):
		var npc := ShopNpc.new()
		npc.shop_id = str(def["id"])
		var at: Array = def.get("position", [0, 14])
		npc.position = Vector3(float(at[0]), 0.0, float(at[1]))
		add_child(npc)
		shop_npcs.append(npc)


## Places the enemy camps listed in TSM_World_Camps.json.
func _spawn_camps() -> void:
	var map_rules: Dictionary = DataRegistry.get_config("world_camps").get("map_1", {})
	for def in map_rules.get("camps", []):
		var camp := EnemyCamp.new()
		camp.setup(def, map_rules, self)
		add_child(camp)
		camps.append(camp)
		camp.tick(0.0)     # enemies near the start appear at once


## Puts a training dummy in the world (also used by tests).
func add_dummy(at: Vector3) -> TrainingDummy:
	var dummy := TrainingDummy.new()
	dummy.position = at
	add_child(dummy)
	return dummy


# ---------- world ----------

func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = TSMTheme.BG
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false    # keep it light for phones
	add_child(_sun)

	# The sky follows the time of day (a real 24 hour cycle).
	day_night = DayNight.new()
	add_child(day_night)
	day_night.setup(_sun, _environment, MAP_ID)


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
	plane.size = Vector2(WORLD_SIZE * 3.0, WORLD_SIZE * 3.0)     # reaches past the walls, to the mountains
	var material := StandardMaterial3D.new()
	material.albedo_texture = _checker_texture()
	material.uv1_scale = Vector3(WORLD_SIZE * 3.0 / 4.0, WORLD_SIZE * 3.0 / 4.0, 1.0)
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


## Places the waypoint obelisks listed in TSM_Maps.json.
func _spawn_waypoints() -> void:
	for entry in MapData.waypoints(MAP_ID):
		var waypoint := Waypoint.new()
		waypoint.waypoint_id = str(entry["id"])
		var at := MapData.position_of(entry)
		waypoint.position = Vector3(at.x, 0.0, at.y)
		add_child(waypoint)
		waypoints.append(waypoint)


## Places the healing fountains listed in TSM_Maps.json.
func _spawn_fountains() -> void:
	for entry in MapData.fountains(MAP_ID):
		var fountain := HealingFountain.new()
		fountain.fountain_id = str(entry["id"])
		var at := MapData.position_of(entry)
		fountain.position = Vector3(at.x, 0.0, at.y)
		add_child(fountain)
		fountains.append(fountain)


## Trees, rocks, mountains and the temple, kept away from the start, the market,
## the camps, the waypoints and the fountains.
func _build_decor() -> void:
	var reserved: Array = [[Vector2.ZERO, 10.0]]
	for shop in DataRegistry.get_config("shop_rules").get("shops", []):
		reserved.append([MapData.position_of(shop), 5.0])
	for camp in DataRegistry.get_config("world_camps").get(MAP_ID, {}).get("camps", []):
		reserved.append([MapData.position_of(camp), float(camp.get("radius", 8)) + 4.0])
	for entry in MapData.waypoints(MAP_ID):
		reserved.append([MapData.position_of(entry), 4.5])
	for entry in MapData.fountains(MAP_ID):
		reserved.append([MapData.position_of(entry), 6.0])
	decor = MapDecor.new()
	add_child(decor)
	decor.build(MAP_ID, reserved)


## Removes all the scenery (tests use this to get an empty field).
func clear_decor() -> void:
	if decor != null:
		decor.clear()
		decor.queue_free()
		decor = null


func _checker_texture() -> ImageTexture:
	var image := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dark := ((x >> 5) + (y >> 5)) % 2 == 0
			image.set_pixel(x, y, Color("27342b") if dark else Color("2f3d32"))
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

	combat_hud = CombatHud.new()
	hud.add_child(combat_hud)
	combat_hud.setup(player)
	combat_hud.sign_out_requested.connect(_on_sign_out)

	var hint := Label.new()
	hint.visible = not DisplayServer.is_touchscreen_available()
	hint.text = "Move: WASD or left thumb  |  Attack: Space / F or the ATK button  |  Look: right mouse or drag  |  Walk over loot to pick it up"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", TSMTheme.MUTED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -44
	hint.offset_right = 1300
	hint.offset_bottom = -12
	hud.add_child(hint)


func _on_sign_out() -> void:
	await Session.flush()      # send kills and loot that are still waiting
	FirebaseService.sign_out()
	FlowRouter.go_to_auth(get_tree())
