class_name KeyboardAvoider
extends Node
## Lifts a screen above the on-screen keyboard (phones) so the field you are
## typing in stays visible. Add it as a child of the screen and set `content`
## to the full-screen container that holds the form.
## Does nothing on desktop, where there is no on-screen keyboard.

const MARGIN := 24.0     # space kept between the field and the keyboard
const SPEED := 14.0

var content: Control
var _shift: float = 0.0


## How far (in screen units) the content must move up so that the bottom of
## the field ends above the keyboard.
static func shift_needed(field_bottom: float, viewport_height: float,
		keyboard_height: float, margin: float = MARGIN) -> float:
	var free_bottom := viewport_height - keyboard_height - margin
	return maxf(0.0, field_bottom - free_bottom)


func _process(delta: float) -> void:
	if content == null or not content.is_inside_tree():
		return

	var target := 0.0
	
	# Only check the virtual keyboard if the current display server actually supports it
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var keyboard_px := DisplayServer.virtual_keyboard_get_height()
		if keyboard_px > 0:
			var focus := content.get_viewport().gui_get_focus_owner()
			if focus != null and content.is_ancestor_of(focus):
				var viewport_h := content.get_viewport().get_visible_rect().size.y
				var window_h := maxf(float(DisplayServer.window_get_size().y), 1.0)
				var keyboard_units := float(keyboard_px) * viewport_h / window_h
				# The field's rectangle already includes the current shift.
				var field_bottom := focus.get_global_rect().end.y + _shift
				target = shift_needed(field_bottom, viewport_h, keyboard_units)

	_shift = lerpf(_shift, target, clampf(delta * SPEED, 0.0, 1.0))
	if absf(_shift - target) < 0.5:
		_shift = target
	content.position.y = -_shift
