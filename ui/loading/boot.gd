extends Control
## Boot scene: splash banner, data check, then straight to the right screen:
##   valid saved session + character -> loading screen -> world
##   valid saved session, no character -> character creation
##   no / expired session -> login screen

const FADE_TIME := 0.8
const HOLD_TIME := 1.4

@onready var banner_image: TextureRect = $BannerImage
@onready var status: Label = get_node_or_null("Status")
@onready var loading_bar: ProgressBar = get_node_or_null("LoadingBar")

var _bar_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if banner_image:
		banner_image.modulate.a = 0.0
	if loading_bar:
		loading_bar.min_value = 0.0
		loading_bar.max_value = 100.0
		loading_bar.value = _rng.randf_range(3.0, 8.0)
	_set_status("Loading...")
	_run_sequence()


func _set_status(msg: String) -> void:
	if status:
		status.text = msg


func _tween_to(target: float, min_dur: float = 0.45, max_dur: float = 1.0) -> void:
	if not loading_bar:
		return
	var current := loading_bar.value
	var clamped_target := clampf(target, current, 100.0)
	var dur := _rng.randf_range(min_dur, max_dur)
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.set_ease(Tween.EASE_IN_OUT)
	_bar_tween.set_trans(Tween.TRANS_SINE)
	_bar_tween.tween_property(loading_bar, "value", clamped_target, dur)
	await _bar_tween.finished


func _step_toward(cap: float, min_step: float = 4.0, max_step: float = 11.0) -> void:
	if not loading_bar:
		return
	var next_val := minf(cap, loading_bar.value + _rng.randf_range(min_step, max_step))
	if next_val > loading_bar.value:
		await _tween_to(next_val, 0.4, 0.95)


func _run_sequence() -> void:
	# 1) Splash banner after Godot Boot Splash while easing in early progress
	if banner_image:
		var tween := create_tween()
		tween.tween_property(banner_image, "modulate:a", 1.0, FADE_TIME)
		tween.tween_interval(HOLD_TIME)
		_step_toward(26.0, 6.0, 12.0)
		await tween.finished

	await _step_toward(36.0, 5.0, 10.0)

	# 2) Make sure the game data is ready (with realistic increments while waiting)
	if not DataRegistry.loaded:
		while not DataRegistry.loaded and loading_bar and loading_bar.value < 58.0:
			await _step_toward(58.0, 4.0, 9.0)
			if DataRegistry.loaded:
				break
			await get_tree().create_timer(_rng.randf_range(0.15, 0.35)).timeout
		if not DataRegistry.loaded:
			await EventBus.data_loaded

	await _tween_to(maxf(loading_bar.value if loading_bar else 0.0, 62.0), 0.45, 0.85)

	var report := DataRegistry.get_report()
	var error_count: int = report["errors"].size()
	if error_count > 0:
		_set_status("Data problems found: %d (see the Output panel)" % error_count)
		if not OS.is_debug_build():
			return   # release builds stop here instead of running on bad data
		await get_tree().create_timer(2.5).timeout

	# 3) Decide where to go
	await _route()


func _finish_at_100() -> void:
	_set_status("Ready...")
	await _tween_to(100.0, 0.55, 0.95)
	await get_tree().create_timer(0.25).timeout


func _route() -> void:
	_set_status("Checking your session...")
	await _step_toward(78.0, 5.0, 11.0)

	var restore: Dictionary = await FirebaseService.try_restore_session()
	await _step_toward(86.0, 4.0, 8.0)

	if restore["ok"]:
		_set_status("Loading your character...")
		await _step_toward(94.0, 4.0, 8.0)
		await _finish_at_100()
		var flow: Dictionary = await FlowRouter.continue_after_sign_in(get_tree())
		if flow["ok"]:
			return    # the scene is changing
		_set_status(str(flow.get("message", "Could not load your account.")))
		await get_tree().create_timer(2.0).timeout

	await _finish_at_100()
	FlowRouter.go_to_auth(get_tree())
