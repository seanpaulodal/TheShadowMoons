class_name WaypointWindow
extends GameWindow
## The map window: every waypoint of the map with its name, level range and
## distance from you, active ones in blue with a Teleport button, inactive ones in
## red. Teleporting itself (the loading fade and the move) is done by the HUD.

signal teleport_requested(waypoint_id: String)

var _player: PlayerController
var _map_id: String = "map_1"
var _summary: Label
var _list: VBoxContainer
var _message: Label


func setup(player: PlayerController, map_id: String) -> void:
	_player = player
	_map_id = map_id
	build("MAP")
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 24)
	_summary.add_theme_color_override("font_color", TSMTheme.ACCENT)
	body.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 20)
	body.add_child(_message)
	Session.character_changed.connect(func() -> void:
		if visible:
			refresh())


func show_message(text: String, is_error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", TSMTheme.ERROR if is_error else TSMTheme.OK)


func refresh() -> void:
	if _list == null or not Session.has_character():
		return
	var map := MapData.get_map(_map_id)
	var entries := MapData.waypoints(_map_id)
	_summary.text = "%s   -   %d / %d waypoints active" % [str(map.get("name", "")),
			WaypointRules.unlocked_count(Session.character, _map_id), entries.size()]

	clear_children(_list)
	for entry in entries:
		_list.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> Control:
	var waypoint_id := str(entry["id"])
	var active := WaypointRules.is_unlocked(Session.character, waypoint_id)
	var at := MapData.position_of(entry)
	var distance := Vector2(_player.global_position.x, _player.global_position.z).distance_to(at)
	var range_: Array = entry.get("level_range", [1, 1])

	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var state := Label.new()
	state.text = "Active" if active else "Inactive"
	state.custom_minimum_size = Vector2(120, 0)
	state.add_theme_font_size_override("font_size", 20)
	state.add_theme_color_override("font_color", Color("4aa8ff") if active else Color("ff4a4a"))
	row.add_child(state)

	var name_label := Label.new()
	name_label.text = str(entry["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", TSMTheme.TEXT if active else TSMTheme.MUTED)
	row.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Lv %d - %d" % [int(range_[0]), int(range_[1])]
	level_label.custom_minimum_size = Vector2(130, 0)
	level_label.add_theme_color_override("font_color", TSMTheme.MUTED)
	row.add_child(level_label)

	var distance_label := Label.new()
	distance_label.text = WaypointRules.distance_text(distance)
	distance_label.custom_minimum_size = Vector2(110, 0)
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	distance_label.add_theme_color_override("font_color", TSMTheme.MUTED)
	row.add_child(distance_label)

	var button := Button.new()
	button.text = "Teleport"
	button.custom_minimum_size = Vector2(170, 64)
	button.disabled = not active
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(_on_teleport.bind(waypoint_id))
	row.add_child(button)
	return panel


func _on_teleport(waypoint_id: String) -> void:
	teleport_requested.emit(waypoint_id)
