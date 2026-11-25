class_name Minimap
extends Control
## The minimap. Small and round in the corner: it follows you and shows what is
## within 45 metres. Tap it and it opens into the whole map, with a legend. It is
## drawn directly (no second camera), so it is cheap on a phone.
##
## Markers: you, enemies (with their level on the big map), loot, shopkeepers,
## waypoints (blue = active, red = inactive) and healing fountains.

signal toggled(expanded: bool)

const COMPACT_SIZE := 230.0
const COMPACT_RANGE := 45.0
const EXPANDED_SIZE := Vector2(900, 640)
const LEGEND_WIDTH := 270.0

## What each marker means (name, kind). The colours are in COLORS.
const LEGEND := [
	["You", "player"], ["Enemy", "enemy"], ["Loot", "loot"], ["Shopkeeper", "npc"],
	["Waypoint (active)", "waypoint_on"], ["Waypoint (inactive)", "waypoint_off"],
	["Healing Fountain", "fountain"],
]
const COLORS := {
	"player": Color("ffffff"), "enemy": Color("ff5050"), "loot": Color("ffd23f"),
	"npc": Color("6fe3c1"), "waypoint_on": Color("4aa8ff"), "waypoint_off": Color("ff4a4a"),
	"fountain": Color("8fe8ff"),
}

var expanded: bool = false

var _player: PlayerController
var _map_size: float = 200.0
var _map_name: String = ""
var _markers: Array = []
var _timer: float = 0.0


func setup(player: PlayerController, map_id: String) -> void:
	_player = player
	var map := MapData.get_map(map_id)
	_map_size = float(map.get("size", 200.0))
	_map_name = str(map.get("name", ""))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_layout()


## Where a world position lands on the map picture. `centre` is the world point
## drawn at `origin`, and `scale` is pixels per metre. World z grows downward.
static func to_map(world: Vector2, centre: Vector2, origin: Vector2, scale: float) -> Vector2:
	return origin + (world - centre) * scale


## True when a spot (relative to the centre) is inside the round minimap.
static func in_circle(offset: Vector2, range_metres: float) -> bool:
	return offset.length() <= range_metres


func toggle() -> void:
	expanded = not expanded
	_apply_layout()
	toggled.emit(expanded)
	queue_redraw()


func collapse() -> void:
	if expanded:
		toggle()


## Everything that should be marked: [{"kind", "pos": Vector2, "level"?, "name"?}].
func collect_markers() -> Array:
	var result: Array = []
	var tree := get_tree()
	for node in tree.get_nodes_in_group("targetable"):
		if node is Enemy and not (node as Enemy).is_dead():
			var enemy := node as Enemy
			result.append({"kind": "enemy", "pos": _flat(enemy), "level": enemy.combatant.level})
	for node in tree.get_nodes_in_group("loot"):
		result.append({"kind": "loot", "pos": _flat(node)})
	for node in tree.get_nodes_in_group("shop_npc"):
		result.append({"kind": "npc", "pos": _flat(node), "name": (node as ShopNpc).display_name})
	for node in tree.get_nodes_in_group("waypoint"):
		var waypoint := node as Waypoint
		result.append({"kind": "waypoint_on" if waypoint.unlocked else "waypoint_off",
				"pos": _flat(waypoint), "name": waypoint.display_name})
	for node in tree.get_nodes_in_group("fountain"):
		result.append({"kind": "fountain", "pos": _flat(node)})
	return result


func markers() -> Array:
	return _markers


func _flat(node: Node) -> Vector2:
	var at := (node as Node3D).global_position
	return Vector2(at.x, at.z)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.1:
		_timer = 0.0
		_markers = collect_markers()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggle()
		accept_event()


func _apply_layout() -> void:
	if expanded:
		set_anchors_preset(Control.PRESET_CENTER)
		offset_left = -EXPANDED_SIZE.x / 2.0
		offset_right = EXPANDED_SIZE.x / 2.0
		offset_top = -EXPANDED_SIZE.y / 2.0
		offset_bottom = EXPANDED_SIZE.y / 2.0
	else:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -(COMPACT_SIZE + 16.0)
		offset_right = -16.0
		offset_top = 96.0
		offset_bottom = 96.0 + COMPACT_SIZE


# ---------- drawing ----------

func _draw() -> void:
	if _player == null:
		return
	if expanded:
		_draw_expanded()
	else:
		_draw_compact()


func _draw_compact() -> void:
	var middle := Vector2(COMPACT_SIZE, COMPACT_SIZE) / 2.0
	var radius := COMPACT_SIZE / 2.0
	var scale := radius / COMPACT_RANGE
	var centre := Vector2(_player.global_position.x, _player.global_position.z)

	draw_circle(middle, radius, Color(0.04, 0.02, 0.09, 0.82))
	draw_arc(middle, radius * 0.5, 0.0, TAU, 40, Color(0.36, 0.16, 0.55, 0.35), 1.5)
	draw_arc(middle, radius - 2.0, 0.0, TAU, 64, Color("5b2a8c"), 3.0)

	for marker in _markers:
		var offset: Vector2 = (marker["pos"] as Vector2) - centre
		if not in_circle(offset, COMPACT_RANGE - 1.5):
			continue
		_draw_marker(str(marker["kind"]), to_map(marker["pos"], centre, middle, scale), 1.0)
	_draw_player(middle, 1.0)
	draw_string(ThemeDB.fallback_font, middle + Vector2(-6, -radius + 20), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("d4af37"))


func _draw_expanded() -> void:
	var map_rect := Rect2(Vector2.ZERO, Vector2(EXPANDED_SIZE.x - LEGEND_WIDTH - 12.0, EXPANDED_SIZE.y))
	var scale := minf(map_rect.size.x, map_rect.size.y) / (_map_size + 10.0)
	var middle := map_rect.size / 2.0

	draw_rect(Rect2(Vector2.ZERO, EXPANDED_SIZE), Color(0.04, 0.02, 0.09, 0.92))
	draw_rect(map_rect, Color(0.08, 0.1, 0.09, 1.0))
	# The edge of the world and a grid line every 50 metres.
	var half := _map_size / 2.0
	draw_rect(Rect2(to_map(Vector2(-half, -half), Vector2.ZERO, middle, scale), Vector2(_map_size, _map_size) * scale),
			Color("5b2a8c"), false, 3.0)
	for step in range(-int(half) + 50, int(half), 50):
		draw_line(to_map(Vector2(step, -half), Vector2.ZERO, middle, scale), to_map(Vector2(step, half), Vector2.ZERO, middle, scale), Color(1, 1, 1, 0.06), 1.0)
		draw_line(to_map(Vector2(-half, step), Vector2.ZERO, middle, scale), to_map(Vector2(half, step), Vector2.ZERO, middle, scale), Color(1, 1, 1, 0.06), 1.0)

	draw_string(ThemeDB.fallback_font, Vector2(14, 28), _map_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("d4af37"))
	for marker in _markers:
		var at := to_map(marker["pos"], Vector2.ZERO, middle, scale)
		_draw_marker(str(marker["kind"]), at, 1.5)
		if marker["kind"] == "enemy":
			draw_string(ThemeDB.fallback_font, at + Vector2(7, 5), str(int(marker["level"])),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffb0b0"))
		elif str(marker["kind"]).begins_with("waypoint"):
			draw_string(ThemeDB.fallback_font, at + Vector2(9, 5), str(marker.get("name", "")),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLORS[str(marker["kind"])])
	_draw_player(to_map(Vector2(_player.global_position.x, _player.global_position.z), Vector2.ZERO, middle, scale), 1.5)

	# Legend.
	var legend_left := map_rect.size.x + 12.0
	draw_string(ThemeDB.fallback_font, Vector2(legend_left + 8, 36), "Legend", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("d4af37"))
	var y := 76.0
	for entry in LEGEND:
		_draw_marker(str(entry[1]), Vector2(legend_left + 20, y - 6), 1.6)
		draw_string(ThemeDB.fallback_font, Vector2(legend_left + 44, y), str(entry[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("e8e0f0"))
		y += 42.0
	draw_string(ThemeDB.fallback_font, Vector2(legend_left + 8, EXPANDED_SIZE.y - 18), "Tap the map to close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("9a8fb0"))


func _draw_marker(kind: String, at: Vector2, size: float) -> void:
	var color: Color = COLORS.get(kind, Color.WHITE)
	match kind:
		"enemy":
			draw_circle(at, 3.5 * size, color)
		"loot":
			draw_rect(Rect2(at - Vector2(2.5, 2.5) * size, Vector2(5, 5) * size), color)
		"npc":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5) * size, at + Vector2(5, 4) * size, at + Vector2(-5, 4) * size]), color)
		"fountain":
			draw_arc(at, 4.5 * size, 0.0, TAU, 12, color, 2.0)
			draw_circle(at, 1.8 * size, color)
		"waypoint_on":
			_draw_diamond(at, 5.5 * size, color, true)
		"waypoint_off":
			_draw_diamond(at, 5.5 * size, color, false)
		"player":
			_draw_player(at, size)


func _draw_diamond(at: Vector2, radius: float, color: Color, filled: bool) -> void:
	var points := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 2.0)


## An arrow pointing the way the camera looks.
func _draw_player(at: Vector2, size: float) -> void:
	var yaw := _player.facing_yaw()
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([
		at + forward * 8.0 * size, at - forward * 5.0 * size + side * 5.0 * size,
		at - forward * 2.0 * size, at - forward * 5.0 * size - side * 5.0 * size]), COLORS["player"])
