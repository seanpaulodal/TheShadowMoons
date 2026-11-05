extends Node
## FirebaseService (autoload): Firebase Authentication through the REST API.
## No addon needed. M2.2 adds session saving and auto-login. Firestore comes in M2.3.

signal signed_in(user_id: String)
signal signed_out

const CONFIG_PATH := "res://config/firebase_config.cfg"
const SESSION_PATH := "user://session.dat"
const SIGN_UP_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s"
const SIGN_IN_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s"
const REFRESH_URL := "https://securetoken.googleapis.com/v1/token?key=%s"
const RESET_URL := "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=%s"
const REFRESH_MARGIN_SECONDS := 120

const FRIENDLY_ERRORS := {
	"EMAIL_EXISTS": "That email is already registered.",
	"INVALID_EMAIL": "That email address isn't valid.",
	"WEAK_PASSWORD": "Password must be at least 6 characters.",
	"INVALID_LOGIN_CREDENTIALS": "Wrong email or password.",
	"EMAIL_NOT_FOUND": "No account uses that email.",
	"INVALID_PASSWORD": "Wrong email or password.",
	"USER_DISABLED": "This account has been disabled.",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "Too many attempts. Try again later.",
	"OPERATION_NOT_ALLOWED": "Email/password sign-in is not enabled in Firebase.",
	"NO_SESSION": "No saved session.",
	"TOKEN_EXPIRED": "Your session has expired. Please sign in again.",
	"INVALID_REFRESH_TOKEN": "Your session is no longer valid. Please sign in again.",
	"USER_NOT_FOUND": "This account no longer exists.",
}

var api_key: String = ""
var project_id: String = ""
var uid: String = ""
var user_email: String = ""
var id_token: String = ""
var refresh_token: String = ""
var _expires_at: int = 0


func _ready() -> void:
	_load_config()


func is_configured() -> bool:
	return api_key != "" and project_id != ""


func is_signed_in() -> bool:
	return uid != "" and id_token != ""


func sign_up(email: String, password: String) -> Dictionary:
	return await _auth_request(SIGN_UP_URL, email, password)


func sign_in(email: String, password: String) -> Dictionary:
	return await _auth_request(SIGN_IN_URL, email, password)


## Sends Firebase's password-reset email. Result: {"ok": true} or a failure.
func send_password_reset(email: String) -> Dictionary:
	if not is_configured():
		return _fail("NOT_CONFIGURED", "Firebase is not configured.")
	var body := {"requestType": "PASSWORD_RESET", "email": email.strip_edges()}
	var response: Dictionary = await _post_json(RESET_URL % api_key, body)
	if not response["ok"]:
		return _fail(response["error"])
	return {"ok": true}


func sign_out() -> void:
	_clear_memory()
	_delete_session_file()
	signed_out.emit()


## Call once at startup. Returns {"ok": true, "uid": ...} when the saved
## session is still valid, so the login screen can be skipped.
func try_restore_session() -> Dictionary:
	if not is_configured():
		return _fail("NOT_CONFIGURED", "Firebase is not configured.")

	var saved := _load_session()
	if saved.is_empty() or str(saved.get("refresh_token", "")) == "":
		return _fail("NO_SESSION")

	refresh_token = str(saved["refresh_token"])
	uid = str(saved.get("uid", ""))
	user_email = str(saved.get("email", ""))

	var result: Dictionary = await refresh_session()
	if result["ok"]:
		signed_in.emit(uid)
		return result

	# Forget the saved session only when the server rejected it.
	# If the phone is simply offline, keep it for next time.
	var code: String = result["error"]
	_clear_memory()
	if not _is_network_problem(code):
		_delete_session_file()
	return result


## Exchanges the refresh token for a new id token.
func refresh_session() -> Dictionary:
	if refresh_token == "":
		return _fail("NO_SESSION")
	if not is_configured():
		return _fail("NOT_CONFIGURED", "Firebase is not configured.")

	var body := "grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode()
	var response: Dictionary = await _post(
			REFRESH_URL % api_key, body, "application/x-www-form-urlencoded")
	if not response["ok"]:
		return _fail(response["error"])

	var data: Dictionary = response["data"]
	id_token = str(data.get("id_token", ""))
	refresh_token = str(data.get("refresh_token", refresh_token))
	uid = str(data.get("user_id", uid))
	_expires_at = int(Time.get_unix_time_from_system()) + int(data.get("expires_in", "3600"))
	_save_session()
	return {"ok": true, "uid": uid}


## Call before any database request. Refreshes the token if it is about to expire.
func ensure_fresh_token() -> bool:
	if not is_signed_in():
		return false
	if Time.get_unix_time_from_system() < _expires_at - REFRESH_MARGIN_SECONDS:
		return true
	var result: Dictionary = await refresh_session()
	return result["ok"]


# ---------- Internals ----------

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_error("[FirebaseService] Cannot read %s" % CONFIG_PATH)
		return
	api_key = str(cfg.get_value("firebase", "api_key", ""))
	project_id = str(cfg.get_value("firebase", "project_id", ""))
	if not is_configured() or api_key.begins_with("PASTE_"):
		push_error("[FirebaseService] api_key / project_id not set in %s" % CONFIG_PATH)
		api_key = ""


func _auth_request(url_template: String, email: String, password: String) -> Dictionary:
	if not is_configured():
		return _fail("NOT_CONFIGURED", "Firebase is not configured.")
	var body := {
		"email": email.strip_edges(),
		"password": password,
		"returnSecureToken": true,
	}
	var response: Dictionary = await _post_json(url_template % api_key, body)
	if not response["ok"]:
		return _fail(response["error"])

	var data: Dictionary = response["data"]
	uid = str(data.get("localId", ""))
	user_email = str(data.get("email", email))
	id_token = str(data.get("idToken", ""))
	refresh_token = str(data.get("refreshToken", ""))
	_expires_at = int(Time.get_unix_time_from_system()) + int(data.get("expiresIn", "3600"))
	_save_session()
	signed_in.emit(uid)
	return {"ok": true, "uid": uid}


func _post_json(url: String, body: Dictionary) -> Dictionary:
	return await _post(url, JSON.stringify(body), "application/json")


func _post(url: String, body_text: String, content_type: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: " + content_type])
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body_text)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "REQUEST_FAILED_%d" % err}

	var result: Array = await http.request_completed
	http.queue_free()

	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "NETWORK_ERROR_%d" % int(result[0])}

	var code: int = result[1]
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed if parsed is Dictionary else {}

	if code >= 200 and code < 300:
		return {"ok": true, "data": data}

	var message := "HTTP_%d" % code
	if data.has("error") and data["error"] is Dictionary:
		message = str(data["error"].get("message", message))
	return {"ok": false, "error": message}


func _fail(raw_error: String, message: String = "") -> Dictionary:
	var code := raw_error.split(" ")[0]    # e.g. "WEAK_PASSWORD : ..." -> "WEAK_PASSWORD"
	if message == "":
		message = FRIENDLY_ERRORS.get(code, "Something went wrong (%s)." % code)
		if code.begins_with("NETWORK_ERROR") or code.begins_with("REQUEST_FAILED"):
			message = "No connection to the server. Check your internet."
	return {"ok": false, "error": code, "message": message}


func _is_network_problem(code: String) -> bool:
	return code.begins_with("NETWORK_ERROR") or code.begins_with("REQUEST_FAILED") \
			or code.begins_with("HTTP_5")


func _clear_memory() -> void:
	uid = ""
	user_email = ""
	id_token = ""
	refresh_token = ""
	_expires_at = 0


# ---------- Session file (encrypted, stored in user://) ----------
# The key is derived from the device id. This hides the file from casual
# reading; it is not a substitute for Firebase security rules.

func _session_key() -> String:
	var device := OS.get_unique_id()
	if device == "":
		device = "tsm_fallback_device"
	return "tsm_session_" + device


func _save_session() -> void:
	var file := FileAccess.open_encrypted_with_pass(
			SESSION_PATH, FileAccess.WRITE, _session_key())
	if file == null:
		push_warning("[FirebaseService] Could not save session file.")
		return
	file.store_string(JSON.stringify({
		"uid": uid,
		"email": user_email,
		"refresh_token": refresh_token,
	}))
	file.close()


func _load_session() -> Dictionary:
	if not FileAccess.file_exists(SESSION_PATH):
		return {}
	var file := FileAccess.open_encrypted_with_pass(
			SESSION_PATH, FileAccess.READ, _session_key())
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _delete_session_file() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)
