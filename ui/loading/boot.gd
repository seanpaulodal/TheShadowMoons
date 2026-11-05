extends Control
## Boot scene: logo, splash, data check, then straight to the right screen:
##   valid saved session + character -> loading screen -> world
##   valid saved session, no character -> character creation
##   no / expired session -> login screen

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
	# 1) Logo first, 2) splash (tagline for now)
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, FADE_TIME)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(tagline, "modulate:a", 1.0, FADE_TIME)
	tween.tween_interval(HOLD_TIME)
	await tween.finished

	# 3) Make sure the game data is ready
	if not DataRegistry.loaded:
		await EventBus.data_loaded

	var report := DataRegistry.get_report()
	var error_count: int = report["errors"].size()
	if error_count > 0:
		status.text = "Data problems found: %d (see the Output panel)" % error_count
		if not OS.is_debug_build():
			return   # release builds stop here instead of running on bad data
		await get_tree().create_timer(2.5).timeout

	# 4) Decide where to go
	await _route()


func _route() -> void:
	status.text = "Checking your session..."
	var restore: Dictionary = await FirebaseService.try_restore_session()
	if restore["ok"]:
		status.text = "Loading your character..."
		var flow: Dictionary = await FlowRouter.continue_after_sign_in(get_tree())
		if flow["ok"]:
			return    # the scene is changing
		status.text = str(flow.get("message", "Could not load your account."))
		await get_tree().create_timer(2.0).timeout
	FlowRouter.go_to_auth(get_tree())
