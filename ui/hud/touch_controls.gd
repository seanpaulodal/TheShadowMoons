class_name TouchControls
extends CanvasLayer
## Phone controls: a floating joystick on the left part of the screen and a
## "drag to look" area on the right part. On desktop the same controls work with
## the mouse, because "Emulate Touch From Mouse" is on in the project settings.
##
## Read `move_vector` (x = right, y = back; so pushing up gives y = -1) and call
## `consume_look_delta()` once per frame.

const JOYSTICK_RADIUS := 110.0
const KNOB_RADIUS := 46.0
const DEAD_ZONE := 0.12
const LOOK_SENSITIVITY := 0.0045
const MOVE_ZONE_RATIO := 0.45     # left 45% of the screen starts the joystick

var move_vector: Vector2 = Vector2.ZERO

var _look_delta: Vector2 = Vector2.ZERO
var _joystick_index: int = -1
var _look_index: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _joystick_position: Vector2 = Vector2.ZERO
var _view: Control


func _ready() -> void:
	layer = 1
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_joystick)
	add_child(_view)


## How much the player dragged on the look area since the last call.
func consume_look_delta() -> Vector2:
	var result := _look_delta
	_look_delta = Vector2.ZERO
	return result


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _notification(what: int) -> void:
	# Letting go of everything when the app loses focus avoids a stuck joystick.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_joystick()
		_look_index = -1


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var width := get_viewport().get_visible_rect().size.x
		if event.position.x < width * MOVE_ZONE_RATIO:
			if _joystick_index == -1:
				_joystick_index = event.index
				_joystick_origin = event.position
				_joystick_position = event.position
				move_vector = Vector2.ZERO
				_view.queue_redraw()
		elif _look_index == -1:
			_look_index = event.index
	else:
		if event.index == _joystick_index:
			_reset_joystick()
		elif event.index == _look_index:
			_look_index = -1


func _on_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_index:
		var drag_offset := event.position - _joystick_origin
		_joystick_position = _joystick_origin + drag_offset.limit_length(JOYSTICK_RADIUS)
		var strength := clampf(drag_offset.length() / JOYSTICK_RADIUS, 0.0, 1.0)
		if strength < DEAD_ZONE:
			move_vector = Vector2.ZERO
		else:
			move_vector = drag_offset.normalized() * strength
		_view.queue_redraw()
	elif event.index == _look_index:
		_look_delta += event.relative * LOOK_SENSITIVITY


func _reset_joystick() -> void:
	_joystick_index = -1
	move_vector = Vector2.ZERO
	if _view != null:
		_view.queue_redraw()


func _draw_joystick() -> void:
	if _joystick_index == -1:
		return
	_view.draw_circle(_joystick_origin, JOYSTICK_RADIUS, Color(0.36, 0.16, 0.55, 0.22))
	_view.draw_arc(_joystick_origin, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(0.36, 0.16, 0.55, 0.7), 3.0)
	_view.draw_circle(_joystick_position, KNOB_RADIUS, Color(0.83, 0.69, 0.22, 0.55))
