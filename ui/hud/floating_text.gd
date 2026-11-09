class_name FloatingText
extends RefCounted
## Damage numbers and "MISS" that float up above a fighter and fade out.
## Looks only: the damage was already worked out before this is called.

const MAX_ACTIVE := 40
const RISE := 1.6
const LIFETIME := 1.0

static var _active: int = 0

const ELEMENT_COLORS := {
	"fire": Color("ff8a3d"), "water": Color("5cb8ff"), "ice": Color("9fe6ff"),
	"shock": Color("ffe94d"), "earth": Color("b08a5a"), "nature": Color("7be07b"),
	"poison": Color("8fe36b"), "holy": Color("fff3b0"), "dark": Color("b07cff"),
}


static func active_count() -> int:
	return _active


## What to show for an attack result: {"text", "color", "scale"}.
static func describe(result: Dictionary) -> Dictionary:
	var outcome := str(result.get("outcome", "hit"))
	if outcome == "miss":
		return {"text": "MISS", "color": Color("b8b0c8"), "scale": 0.9}
	if outcome == "parry":
		return {"text": "PARRY", "color": Color("7fb4ff"), "scale": 1.0}
	var damage := int(result.get("damage", 0))
	if outcome == "dot":
		var element := ElementalSystem.canonical(str(result.get("element", "")))
		var color: Color = ELEMENT_COLORS.get(element[0], Color("e8e0f0")) if not element.is_empty() else Color("e8e0f0")
		return {"text": str(damage), "color": color, "scale": 0.8}
	if result.get("is_crit", false):
		return {"text": "CRIT %d!" % damage, "color": Color("ffd23f"), "scale": 1.5}
	if result.get("blocked", false):
		return {"text": "(block) %d" % damage, "color": Color("9aa4b8"), "scale": 0.95}
	var elemental := int(result.get("elemental", 0))
	if elemental > 0 and not str(result.get("element", "")).is_empty():
		var parts := ElementalSystem.canonical(str(result.get("element", "")))
		if not parts.is_empty() and ELEMENT_COLORS.has(parts[0]) and elemental * 3 > damage:
			return {"text": str(damage), "color": ELEMENT_COLORS[parts[0]], "scale": 1.1}
	return {"text": str(damage), "color": Color("ffffff"), "scale": 1.0}


## Shows a result above `world_position` (a point in the 3D world).
static func show_result(parent: Node, world_position: Vector3, result: Dictionary) -> void:
	var look := describe(result)
	spawn(parent, world_position, str(look["text"]), look["color"], float(look["scale"]))


static func show_heal(parent: Node, world_position: Vector3, amount: int) -> void:
	spawn(parent, world_position, "+%d" % amount, Color("7be07b"), 0.9)


static func spawn(parent: Node, world_position: Vector3, text: String, color: Color, text_scale: float = 1.0) -> void:
	if _active >= MAX_ACTIVE or parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = int(56.0 * text_scale)
	label.pixel_size = 0.006
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	# A little sideways spread so numbers from fast hits do not sit on each other.
	parent.add_child(label)
	label.global_position = world_position + Vector3(randf_range(-0.35, 0.35), 0.0, 0.0)
	_active += 1

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + RISE, LIFETIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME).set_delay(LIFETIME * 0.4)
	tween.chain().tween_callback(func() -> void:
		_active = maxi(0, _active - 1)
		label.queue_free())
