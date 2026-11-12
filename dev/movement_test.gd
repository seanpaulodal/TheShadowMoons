extends Node
## DEV ONLY. Checks walking, gravity, collisions and the touch controls (M4).
## Run with F6 and read the Output panel. It needs no login: it makes up a
## test character. The expected numbers use the placeholder class data (rogue).

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	Session.character = {"name": "TestHero", "class_id": "rogue", "level": 1}
	Session.slot = 1

	await _test_touch_controls()
	await _test_movement()
	Session.clear()
	print("[move] RESULT: %d passed, %d failed" % [_passed, _failed])


func _report(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[move] PASS  ", label)
	else:
		_failed += 1
		print("[move] FAIL  %s  (%s)" % [label, detail])


func _in_range(label: String, value: float, low: float, high: float) -> void:
	_report(label, value >= low and value <= high, "%s is outside %s .. %s" % [str(value), str(low), str(high)])


func _touch(controls: TouchControls, index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	controls._input(event)


func _drag(controls: TouchControls, index: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	controls._input(event)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


# ---------- touch controls ----------

func _test_touch_controls() -> void:
	print("[move] --- touch controls ---")
	var controls := TouchControls.new()
	add_child(controls)
	await get_tree().process_frame
	var size := get_viewport().get_visible_rect().size
	var left_start := Vector2(size.x * 0.2, size.y * 0.7)
	var right_start := Vector2(size.x * 0.8, size.y * 0.5)

	_report("joystick starts still", controls.move_vector == Vector2.ZERO)
	_touch(controls, 0, left_start, true)
	_drag(controls, 0, left_start + Vector2(TouchControls.JOYSTICK_RADIUS, 0), Vector2(110, 0))
	_in_range("push right: x is about 1", controls.move_vector.x, 0.99, 1.01)
	_in_range("push right: y is about 0", controls.move_vector.y, -0.01, 0.01)
	_drag(controls, 0, left_start + Vector2(0, -TouchControls.JOYSTICK_RADIUS * 0.5), Vector2(0, -55))
	_in_range("push up half way: y is about -0.5", controls.move_vector.y, -0.51, -0.49)
	_drag(controls, 0, left_start + Vector2(400, 0), Vector2(300, 0))
	_in_range("pushing far is limited to length 1", controls.move_vector.length(), 0.99, 1.01)
	_drag(controls, 0, left_start + Vector2(5, 0), Vector2(-395, 0))
	_report("small wiggle inside the dead zone does nothing", controls.move_vector == Vector2.ZERO)
	_drag(controls, 0, left_start + Vector2(0, 80), Vector2(-5, 80))
	_touch(controls, 0, left_start, false)
	_report("letting go stops the joystick", controls.move_vector == Vector2.ZERO)

	_touch(controls, 1, right_start, true)
	_drag(controls, 1, right_start + Vector2(100, 40), Vector2(100, 40))
	var look := controls.consume_look_delta()
	_in_range("dragging right looks right (x)", look.x, 0.4, 0.5)
	_in_range("dragging down looks down (y)", look.y, 0.15, 0.2)
	_report("look amount is used up once read", controls.consume_look_delta() == Vector2.ZERO)
	_touch(controls, 1, right_start, false)

	# Two thumbs at once.
	_touch(controls, 0, left_start, true)
	_touch(controls, 1, right_start, true)
	_drag(controls, 0, left_start + Vector2(0, -110), Vector2(0, -110))
	_drag(controls, 1, right_start + Vector2(50, 0), Vector2(50, 0))
	_in_range("two thumbs: moving up while looking", controls.move_vector.y, -1.01, -0.99)
	_in_range("two thumbs: look x", controls.consume_look_delta().x, 0.2, 0.25)
	_touch(controls, 0, left_start, false)
	_touch(controls, 1, right_start, false)
	controls.queue_free()


# ---------- movement in the world ----------

func _test_movement() -> void:
	print("[move] --- movement ---")
	var world: Node3D = load("res://maps/world_test.tscn").instantiate()
	add_child(world)
	await _frames(40)
	var player: PlayerController = world.player
	# The world now has training dummies in it. This test only measures walking,
	# so clear them out of the way.
	for camp in world.camps:
		camp.queue_free()
	for node in get_tree().get_nodes_in_group("targetable"):
		node.queue_free()
	await _frames(2)
	_report("world built a player", player != null)
	if player == null:
		return

	var expected_speed: float = StatCalculator.calculate("rogue", 1)["stats"]["move_speed"]
	_in_range("speed comes from the stat calculator (rogue)", player.move_speed(), expected_speed - 0.01, expected_speed + 0.01)
	_report("player landed on the ground", player.is_on_floor())
	_in_range("standing height is ground level", player.global_position.y, -0.05, 0.05)

	var start := player.global_position
	await _frames(30)
	_report("standing still stays still", player.global_position.distance_to(start) < 0.01)

	# Walk forward for one second (the camera looks down -Z at the start).
	start = player.global_position
	player.move_override = Vector2(0, -1)
	await _frames(60)
	var walked := player.global_position - start
	_in_range("forward for 1 s: moved about the move_speed in -Z", -walked.z, expected_speed * 0.85, expected_speed * 1.02)
	_in_range("forward: no sideways drift", walked.x, -0.05, 0.05)
	_in_range("still on the ground while walking", player.global_position.y, -0.05, 0.05)
	_in_range("full speed reached", Vector2(player.velocity.x, player.velocity.z).length(), expected_speed - 0.05, expected_speed + 0.05)

	# Half stick = half speed.
	player.move_override = Vector2(0, 0.5)
	await _frames(30)
	_in_range("half stick walks at half speed", Vector2(player.velocity.x, player.velocity.z).length(),
			expected_speed * 0.5 - 0.05, expected_speed * 0.5 + 0.05)

	# Diagonal is not faster than straight.
	player.move_override = Vector2(1, -1)
	await _frames(30)
	_in_range("diagonal is not faster", Vector2(player.velocity.x, player.velocity.z).length(),
			expected_speed - 0.05, expected_speed + 0.05)

	# Movement follows the camera: turn the camera 90 degrees, forward becomes -X.
	player.move_override = Vector2.ZERO
	await _frames(30)
	player.set_facing_yaw(PI / 2.0)
	start = player.global_position
	player.move_override = Vector2(0, -1)
	await _frames(30)
	walked = player.global_position - start
	_report("after turning the camera, forward goes toward -X", walked.x < -2.0 and absf(walked.z) < 0.3,
			"moved %s" % str(walked))
	player.move_override = Vector2.ZERO
	player.set_facing_yaw(0.0)
	await _frames(30)

	# Walls: a box in front of the player stops them.
	player.global_position = Vector3(0, 0.2, 40)
	player.velocity = Vector3.ZERO
	world.add_box(Vector3(0, 1.0, 36), Vector3(4, 2, 1))     # front face at z = 36.5
	await _frames(5)
	player.move_override = Vector2(0, -1)
	await _frames(120)
	_in_range("a solid box stops the player (z stays beyond 36.5)", player.global_position.z, 36.5, 37.2)
	player.move_override = Vector2.ZERO

	# The world edge: walk into the invisible wall.
	player.global_position = Vector3(0, 0.2, -95)
	player.velocity = Vector3.ZERO
	player.move_override = Vector2(0, -1)
	await _frames(120)
	_in_range("the world edge stops the player", player.global_position.z, -100.0, -99.0)
	player.move_override = Vector2.ZERO

	# Falling out of the world puts you back at the start.
	player.global_position = Vector3(5, -30, 5)
	await _frames(3)
	_in_range("falling out of the world respawns (y)", player.global_position.y, -0.05, 1.0)
	_in_range("falling out of the world respawns (x)", player.global_position.x, -0.5, 0.5)

	# Stats follow equipment: a speed bonus makes the player faster.
	player.refresh_stats([{"stat": "move_speed", "flat": 3.0}])
	_in_range("a +3 speed bonus is used", player.move_speed(), expected_speed + 2.99, expected_speed + 3.01)
	world.queue_free()
