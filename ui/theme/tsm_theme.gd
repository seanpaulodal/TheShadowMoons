class_name TSMTheme
extends RefCounted
## Shared dark-fantasy look: black and purple with gold accents.
## Use:  some_control.theme = TSMTheme.get_theme()

const BG := Color("07040d")
const PANEL := Color("140a24")
const PANEL_LIGHT := Color("1d1033")
const BORDER := Color("5b2a8c")
const ACCENT := Color("d4af37")
const TEXT := Color("e8e0f0")
const MUTED := Color("9a8fb0")
const ERROR := Color("ff7a7a")
const OK := Color("8fe3a1")

const RARITY_COLORS := {
	"common": Color("c8c8c8"), "uncommon": Color("6fd36f"), "rare": Color("5aa9ff"),
	"epic": Color("b36bff"), "elite": Color("ffb347"), "legendary": Color("ff8a2a"),
	"mythic": Color("ff4d4d"),
}

static var _cached: Theme = null


## Colour for an item or enemy rarity name (Common ... Mythic).
static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity.strip_edges().to_lower(), Color("c8c8c8"))


static func get_theme() -> Theme:
	if _cached == null:
		_cached = _build()
	return _cached


## Red-bordered text field, for fields that currently hold invalid input.
static func error_box() -> StyleBoxFlat:
	return _box(Color("1a0a12"), ERROR)


static func _box(bg: Color, border: Color, pad: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(pad)
	return box


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22

	# Labels
	t.set_color("font_color", "Label", TEXT)

	# Panels
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 24))
	t.set_stylebox("panel", "Panel", _box(PANEL, BORDER, 12))

	# Buttons
	t.set_stylebox("normal", "Button", _box(PANEL_LIGHT, BORDER))
	t.set_stylebox("hover", "Button", _box(Color("2a1650"), ACCENT))
	t.set_stylebox("pressed", "Button", _box(Color("3a1e6b"), ACCENT))
	t.set_stylebox("hover_pressed", "Button", _box(Color("3a1e6b"), ACCENT))
	t.set_stylebox("disabled", "Button", _box(Color("14101c"), Color("2c2438")))
	var focus := _box(Color(0, 0, 0, 0), ACCENT)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color("5d5470"))

	# Text fields
	t.set_stylebox("normal", "LineEdit", _box(Color("0d0718"), BORDER))
	t.set_stylebox("focus", "LineEdit", _box(Color("0d0718"), ACCENT))
	t.set_stylebox("read_only", "LineEdit", _box(Color("0d0718"), Color("2c2438")))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(BORDER, 0.6))

	# Check boxes
	t.set_color("font_color", "CheckBox", MUTED)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", TEXT)

	# Scroll bars (wide enough to grab with a finger)
	var scroll_bg := _box(Color("0d0718"), Color(0, 0, 0, 0), 7)
	var grabber := _box(BORDER, BORDER, 7)
	var grabber_hover := _box(ACCENT, ACCENT, 7)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber_hover)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber_hover)

	# Progress bars
	var bar_bg := _box(Color("0d0718"), BORDER, 4)
	var bar_fill := _box(ACCENT, ACCENT, 4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)

	return t
