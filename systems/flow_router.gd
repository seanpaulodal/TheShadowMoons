class_name FlowRouter
extends RefCounted
## Decides which scene comes next. Keeps the scene paths in one place.

const AUTH_SCENE := "res://ui/auth/auth_screen.tscn"
const CREATION_SCENE := "res://ui/auth/character_creation.tscn"
const WORLD_SCENE := "res://maps/world_test.tscn"
const CHARACTER_SLOT := 1


## Call right after a successful sign-in or restored session.
## Loads the profile and the character, then opens the right scene:
##   character found -> loading screen -> world
##   no character    -> character creation
## Returns {"ok": true} or the failing result (with "message").
static func continue_after_sign_in(tree: SceneTree) -> Dictionary:
	var profile: Dictionary = await Session.ensure_profile()
	if not profile["ok"]:
		return profile

	var loaded: Dictionary = await Session.load_character(CHARACTER_SLOT)
	if not loaded["ok"]:
		return loaded

	if loaded["found"]:
		LoadingScreen.go(tree, WORLD_SCENE)
	else:
		tree.change_scene_to_file(CREATION_SCENE)
	return {"ok": true}


static func go_to_auth(tree: SceneTree) -> void:
	tree.change_scene_to_file(AUTH_SCENE)
