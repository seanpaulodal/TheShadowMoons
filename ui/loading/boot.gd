extends Control
## Boot scene: logo, splash, wait for data, then move on.

const NEXT_SCENE := "res://maps/m0_test.tscn"   # M2 will point this at the auth scene
const FADE_TIME := 1.0
const HOLD_TIME := 1.2

@onready var logo: Label = $Center/Box/Logo
@onready var tagline: Label = $Center/Box/Tagline
@onready var status: Label = $Status


func _ready() -> void:
	logo.modulate.a = 0.0
	tagline.modulate.a = 0.0
	status.text = "Loading..."
	_run_sequence()


func _run_sequence() -> void:
	# 1) Logo first
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, FADE_TIME)
	tween.tween_interval(HOLD_TIME)
	# 2) Splash (tagline for now)
	tween.tween_property(tagline, "modulate:a", 1.0, FADE_TIME)
	tween.tween_interval(HOLD_TIME)
	await tween.finished

	# 3) Make sure data is ready
	if not DataRegistry.loaded:
		await EventBus.data_loaded

	var report := DataRegistry.get_report()
	var error_count: int = report["errors"].size()
	if error_count > 0:
		status.text = "Data problems found: %d (see the Output panel)" % error_count
		if not OS.is_debug_build():
			return   # release builds stop here instead of running on bad data
		await get_tree().create_timer(2.5).timeout

	get_tree().change_scene_to_file(NEXT_SCENE)
