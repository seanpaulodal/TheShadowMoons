class_name GameWindow
extends PanelContainer
## The frame every full-screen window shares: a title, a big close button, and a
## body to fill. Windows start hidden. Call build() once, then open() / close().

signal closed

var body: VBoxContainer

var _title_label: Label


func build(title_text: String) -> void:
	theme = TSMTheme.get_theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_right = -40
	offset_top = 24
	offset_bottom = -24

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", TSMTheme.ACCENT)
	header.add_child(_title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(84, 64)
	close_button.add_theme_font_size_override("font_size", 28)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Redraws the window from the character. Windows override this.
func refresh() -> void:
	pass


# ---------- small helpers the windows share ----------

static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func slot_style(border: Color, selected: bool, filled: bool = true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("160c26") if filled else Color("0b0614")
	box.border_color = TSMTheme.ACCENT if selected else border
	box.set_border_width_all(5 if selected else 3)
	box.set_corner_radius_all(8)
	return box


## Draws item information lines (see ItemInfo.lines) into a container.
static func fill_item_lines(container: VBoxContainer, item_id: String) -> void:
	clear_children(container)
	var title := Label.new()
	title.text = ItemDB.display_name(item_id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TSMTheme.rarity_color(ItemDB.rarity(item_id)))
	container.add_child(title)
	for line in ItemInfo.lines(item_id):
		var label := Label.new()
		label.text = str(line["text"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 19)
		match str(line["kind"]):
			"muted":
				label.add_theme_color_override("font_color", TSMTheme.MUTED)
			"stat":
				label.add_theme_color_override("font_color", TSMTheme.OK)
			"effect":
				label.add_theme_color_override("font_color", Color("ffb36b"))
			"warning":
				label.add_theme_color_override("font_color", TSMTheme.ERROR)
			"price":
				label.add_theme_color_override("font_color", TSMTheme.ACCENT)
		container.add_child(label)
