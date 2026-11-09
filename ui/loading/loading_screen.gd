class_name LoadingScreen
extends Control
## Shows a loading screen, loads the next scene, then switches to it.
## The scene is loaded normally (not on a background thread) because scenes
## whose scripts use autoloads can fail to load from a thread. The bar is
## cosmetic for now; real streaming for large maps is a later optimization.
## Use:  LoadingScreen.go(get_tree(), "res://maps/world_test.tscn")

const SCENE_PATH := "res://ui/loading/loading_screen.tscn"
const MIN_SHOW_SECONDS := 0.8

static var _target: String = ""

var _bar: ProgressBar
var _label: Label
var _elapsed: float = 0.0
var _frames: int = 0
var _done: bool = false
var _packed: PackedScene = null


static func go(tree: SceneTree, target_scene: String) -> void:
	_target = target_scene
	tree.change_scene_to_file(SCENE_PATH)


func _ready() -> void:
	theme = TSMTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TSMTheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(700, 0)
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	var title := Label.new()
	title.text = "THE SHADOW MOONS - PROPHECY UNTOLD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TSMTheme.ACCENT)
	box.add_child(title)

	_label = Label.new()
	_label.text = "Entering the world..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 22)
	box.add_child(_bar)

	if _target == "":
		_label.text = "No scene to load."
		_done = true


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_frames += 1

	# Let the loading screen draw for a couple of frames, then load.
	if _packed == null and _frames >= 3:
		_packed = load(_target) as PackedScene
		if _packed == null:
			_label.text = "Could not load the next scene."
			_done = true
			return

	_bar.value = clampf(_elapsed / MIN_SHOW_SECONDS, 0.0, 1.0)
	if _packed != null and _elapsed >= MIN_SHOW_SECONDS:
		_done = true
		get_tree().change_scene_to_packed(_packed)
