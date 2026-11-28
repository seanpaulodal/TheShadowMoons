class_name QuestWindow
extends GameWindow
## The quest log: main, side and skill quests. Shows active quests with progress
## and lets the player accept new ones they qualify for.

signal quest_started(quest_id: String)
signal quest_finished(quest_id: String)

var _list: VBoxContainer
var _accept_box: VBoxContainer
var _message: Label

func _ready() -> void:
	QuestTracker.quest_accepted.connect(func(qid: String) -> void:
		if visible: refresh())
	QuestTracker.quest_completed.connect(func(qid: String) -> void:
		if visible: refresh())

func setup() -> void:
	build("QUESTS")
	_build_layout()
	refresh()

func _build_layout() -> void:
	var title := Label.new()
	title.text = "Quest Log"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", TSMTheme.ACCENT)
	body.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)

	var active_tab := Button.new()
	active_tab.text = "Active"
	active_tab.toggle_mode = true
	active_tab.button_pressed = true
	active_tab.custom_minimum_size = Vector2(160, 60)
	active_tab.add_theme_font_size_override("font_size", 24)
	tabs.add_child(active_tab)

	var all_tab := Button.new()
	all_tab.text = "All"
	all_tab.toggle_mode = true
	all_tab.custom_minimum_size = Vector2(160, 60)
	all_tab.add_theme_font_size_override("font_size", 24)
	tabs.add_child(all_tab)

	var group := ButtonGroup.new()
	active_tab.button_group = group
	all_tab.button_group = group

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	body.add_child(_list)

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 22)
	_message.add_theme_color_override("font_color", TSMTheme.MUTED)
	body.add_child(_message)

	_accept_box = VBoxContainer.new()
	_accept_box.add_theme_constant_override("separation", 6)
	body.add_child(_accept_box)

	refresh()

func refresh() -> void:
	clear_children(_list)
	clear_children(_accept_box)
	var character := Session.character
	if character.is_empty():
		_message.text = "No character loaded."
		return
	var active_quests := character.get("active_quests", {})
	var completed := character.get("completed_quests", [])
	if active_quests.is_empty() and completed.is_empty():
		_message.text = "No quests yet."
		return
	if not active_quests.is_empty():
		var active_label := Label.new()
		active_label.text = "Active Quests"
		active_label.add_theme_font_size_override("font_size", 26)
		active_label.add_theme_color_override("font_color", TSMTheme.OK)
		_list.add_child(active_label)
		for qid in active_quests.keys():
			var qdata := QuestTracker.get_quest(qid)
			var row := _quest_row(qid, qdata, int(active_quests[qid].get("progress", 0)))
			_list.add_child(row)
	if not completed.is_empty():
		var done_label := Label.new()
		done_label.text = "Completed"
		done_label.add_theme_font_size_override("font_size", 26)
		done_label.add_theme_color_override("font_color", TSMTheme.OK)
		_list.add_child(done_label)
		for qid in completed:
			var qdata := QuestTracker.get_quest(qid)
			var row := Label.new()
			row.text = "✓ " + qdata.get("title", qid)
			row.add_theme_font_size_override("font_size", 22)
			row.add_theme_color_override("font_color", TSMTheme.MUTED)
			_list.add_child(row)

func _quest_row(quest_id: String, quest: Dictionary, progress: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = quest.get("title", quest_id)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TSMTheme.TEXT)
	row.add_child(title)
	var desc := Label.new()
	desc.text = quest.get("desc", "")
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", TSMTheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)
	var prog := Label.new()
	prog.text = "%d/%d" % [progress, quest.get("required", 1)]
	prog.add_theme_font_size_override("font_size", 20)
	prog.add_theme_color_override("font_color", TSMTheme.ACCENT)
	row.add_child(prog)
	return row
