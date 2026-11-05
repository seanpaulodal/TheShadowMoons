class_name PlayerController
extends CharacterBody3D
## The player's body: walking, gravity, and the follow camera.
## Movement speed comes from the stat calculator, so class, level, attribute
## points and equipment all change how fast the character walks.
##
## Controls: WASD / arrow keys or the touch joystick to move, right mouse button
## or dragging the right side of the screen to turn the camera, mouse wheel to zoom.

const GRAVITY := 14.0              # reference value from the design document
const ACCELERATION := 60.0
const TURN_SPEED := 12.0
const FALLBACK_SPEED := 7.0
const FALL_LIMIT := -20.0
const MOUSE_LOOK_SENSITIVITY := 0.004
const PITCH_MIN := -1.3
const PITCH_MAX := -0.05
const DISTANCE_MIN := 3.0
const DISTANCE_MAX := 12.0

const ACTION_KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
}

## Final stats of the character (see StatCalculator). Refresh when gear changes.
var stats: Dictionary = {}
## Optional: touch controls to read the joystick and camera drag from.
var controls: TouchControls
## Used by tests to push the character without a keyboard or touch screen.
var move_override: Vector2 = Vector2.ZERO
var spawn_position: Vector3 = Vector3(0, 1, 0)

var _yaw: float = 0.0
var _pitch: float = -0.4
var _distance: float = 6.5
var _mouse_look: Vector2 = Vector2.ZERO
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D


func _ready() -> void:
	_ensure_input_actions()
	_build_body()
	_build_camera()
	refresh_stats()
	global_position = spawn_position


## Recalculates the stats from the saved character. Call after equipping gear,
## spending attribute points or leveling up.
func refresh_stats(modifiers: Array = [], _mounted: bool = false) -> void:
	var character := Session.character
	var result := StatCalculator.calculate(str(character.get("class_id", "")),
			int(character.get("level", 1)), character.get("attributes", {}), modifiers)
	if result["ok"]:
		stats = result["stats"]
	else:
		stats = {"move_speed": FALLBACK_SPEED}


func move_speed() -> float:
	return float(stats.get("move_speed", FALLBACK_SPEED))


func facing_yaw() -> float:
	return _yaw


func set_facing_yaw(value: float) -> void:
	_yaw = value


func _physics_process(delta: float) -> void:
	var input := _read_move_input().limit_length(1.0)
	var direction := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	var target := direction * move_speed()

	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	velocity.y -= GRAVITY * delta
	move_and_slide()

	# Turn the model toward where we are walking.
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > 0.5:
		var wanted := atan2(-velocity.x, -velocity.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, wanted, clampf(TURN_SPEED * delta, 0.0, 1.0))

	if global_position.y < FALL_LIMIT:
		global_position = spawn_position
		velocity = Vector3.ZERO


func _process(_delta: float) -> void:
	var look := _mouse_look
	_mouse_look = Vector2.ZERO
	if controls != null:
		look += controls.consume_look_delta()
	if look != Vector2.ZERO:
		_yaw -= look.x
		_pitch = clampf(_pitch - look.y, PITCH_MIN, PITCH_MAX)
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position.z = _distance


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_mouse_look += event.relative * MOUSE_LOOK_SENSITIVITY
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.5, DISTANCE_MIN, DISTANCE_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.5, DISTANCE_MIN, DISTANCE_MAX)


func _read_move_input() -> Vector2:
	if move_override != Vector2.ZERO:
		return move_override
	if controls != null and controls.move_vector != Vector2.ZERO:
		return controls.move_vector
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


# ---------- building the body and camera ----------

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.8
	shape.shape = capsule_shape
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	_model = Node3D.new()
	add_child(_model)

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("7a4bd1")
	capsule.material = body_material
	body.mesh = capsule
	body.position = Vector3(0, 0.9, 0)
	_model.add_child(body)

	# A small gold "nose" shows which way the character faces (forward is -Z).
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.22, 0.22, 0.4)
	var nose_material := StandardMaterial3D.new()
	nose_material.albedo_color = TSMTheme.ACCENT
	nose_mesh.material = nose_material
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 1.3, -0.45)
	_model.add_child(nose)

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
	nameplate.position = Vector3(0, 2.5, 0)
	add_child(nameplate)


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.5, 0)
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, _distance)
	_pivot.add_child(_camera)
	_camera.current = true


static func _ensure_input_actions() -> void:
	for action in ACTION_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTION_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
