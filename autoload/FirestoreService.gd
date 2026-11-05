extends Node
## FirestoreService (autoload): minimal Firestore client over the REST API.
## Handles reading and writing documents and converts between plain
## GDScript values and Firestore's typed JSON. Needs FirebaseService.

const BASE_URL := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents"
const COMMIT_URL := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit"
const REQUEST_TIMEOUT := 20.0

const FRIENDLY_ERRORS := {
	"PERMISSION_DENIED": "The database rules blocked this request.",
	"UNAUTHENTICATED": "You are not signed in.",
	"NOT_FOUND": "That data does not exist.",
	"ALREADY_EXISTS": "That data already exists.",
	"UNAVAILABLE": "The database is temporarily unavailable.",
	"DEADLINE_EXCEEDED": "The database took too long to answer.",
	"RESOURCE_EXHAUSTED": "Too many requests. Try again shortly.",
	"FAILED_PRECONDITION": "The database is not set up correctly (is Firestore created?).",
}


# ---------- Public API ----------
# Every function returns a Dictionary with "ok": true/false.
# On failure: {"ok": false, "error": CODE, "message": "..."}.

## Reads one document. Result: {"ok": true, "found": bool, "data": Dictionary}
func get_document(path: String) -> Dictionary:
	var response: Dictionary = await _send(HTTPClient.METHOD_GET, _doc_url(path))
	if response["ok"]:
		var fields: Dictionary = response["data"].get("fields", {})
		return {"ok": true, "found": true, "data": from_fields(fields)}
	if response["error"] == "NOT_FOUND":
		return {"ok": true, "found": false, "data": {}}
	return _fail(response["error"])


## Creates the document, or replaces it completely if it already exists.
func set_document(path: String, data: Dictionary) -> Dictionary:
	var body := {"fields": to_fields(data)}
	var response: Dictionary = await _send(HTTPClient.METHOD_PATCH, _doc_url(path), body)
	if response["ok"]:
		return {"ok": true}
	return _fail(response["error"])


## Changes only the listed top-level fields; other fields stay untouched.
## A listed field that holds a map or array is replaced as a whole.
func update_fields(path: String, data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"ok": true}
	var mask := PackedStringArray()
	for key in data:
		mask.append("updateMask.fieldPaths=" + str(key).uri_encode())
	var url := _doc_url(path) + "?" + "&".join(mask)
	var body := {"fields": to_fields(data)}
	var response: Dictionary = await _send(HTTPClient.METHOD_PATCH, url, body)
	if response["ok"]:
		return {"ok": true}
	return _fail(response["error"])


## Creates several NEW documents in one all-or-nothing step.
## entries: [{"path": "tsm_names/hero", "data": {...}}, ...]
## If any of the documents already exists, or a security rule refuses one of
## them, nothing at all is written. Failure code ALREADY_EXISTS means one of
## the paths was taken.
func create_documents(entries: Array) -> Dictionary:
	var body := {"writes": build_commit_writes(entries)}
	var url: String = COMMIT_URL % FirebaseService.project_id
	var response: Dictionary = await _send(HTTPClient.METHOD_POST, url, body)
	if response["ok"]:
		return {"ok": true}
	return _fail(response["error"])


func build_commit_writes(entries: Array) -> Array:
	var writes: Array = []
	for entry in entries:
		writes.append({
			"update": {
				"name": _doc_name(str(entry["path"])),
				"fields": to_fields(entry["data"]),
			},
			"currentDocument": {"exists": false},
		})
	return writes


# ---------- Value conversion ----------

func to_fields(data: Dictionary) -> Dictionary:
	var fields := {}
	for key in data:
		fields[str(key)] = to_value(data[key])
	return fields


func to_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return {"nullValue": null}
		TYPE_BOOL:
			return {"booleanValue": value}
		TYPE_INT:
			return {"integerValue": str(value)}
		TYPE_FLOAT:
			return {"doubleValue": value}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"stringValue": str(value)}
		TYPE_DICTIONARY:
			return {"mapValue": {"fields": to_fields(value)}}
		TYPE_ARRAY:
			var values: Array = []
			for item in value:
				values.append(to_value(item))
			return {"arrayValue": {"values": values}}
	# Anything else (Vector3, Color, ...) is saved as text. Convert it yourself
	# before saving if you need it back as its original type.
	return {"stringValue": str(value)}


func from_fields(fields: Dictionary) -> Dictionary:
	var data := {}
	for key in fields:
		data[key] = from_value(fields[key])
	return data


func from_value(value: Dictionary) -> Variant:
	if value.has("stringValue"):
		return str(value["stringValue"])
	if value.has("integerValue"):
		return int(str(value["integerValue"]))
	if value.has("doubleValue"):
		return float(value["doubleValue"])
	if value.has("booleanValue"):
		return bool(value["booleanValue"])
	if value.has("timestampValue"):
		return str(value["timestampValue"])
	if value.has("mapValue"):
		return from_fields(value["mapValue"].get("fields", {}))
	if value.has("arrayValue"):
		var out: Array = []
		for item in value["arrayValue"].get("values", []):
			out.append(from_value(item))
		return out
	return null    # nullValue or an unsupported type


# ---------- Internals ----------

func _doc_url(path: String) -> String:
	return (BASE_URL % FirebaseService.project_id) + "/" + path


func _doc_name(path: String) -> String:
	return "projects/%s/databases/(default)/documents/%s" % [FirebaseService.project_id, path]


func _send(method: HTTPClient.Method, url: String, body: Variant = null,
		retried: bool = false) -> Dictionary:
	if not FirebaseService.is_configured():
		return {"ok": false, "error": "NOT_CONFIGURED"}
	if not await FirebaseService.ensure_fresh_token():
		return {"ok": false, "error": "UNAUTHENTICATED"}

	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var headers := PackedStringArray([
		"Authorization: Bearer " + FirebaseService.id_token,
		"Content-Type: application/json",
	])
	var body_text := "" if body == null else JSON.stringify(body)
	var err := http.request(url, headers, method, body_text)
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

	var error_code := "HTTP_%d" % code
	if data.has("error") and data["error"] is Dictionary:
		error_code = str(data["error"].get("status", error_code))

	# An expired login: refresh the token and try once more.
	if error_code == "UNAUTHENTICATED" and not retried:
		var refreshed: Dictionary = await FirebaseService.refresh_session()
		if refreshed["ok"]:
			return await _send(method, url, body, true)
	return {"ok": false, "error": error_code}


func _fail(code: String) -> Dictionary:
	var message: String = FRIENDLY_ERRORS.get(code, "Database error (%s)." % code)
	if code.begins_with("NETWORK_ERROR") or code.begins_with("REQUEST_FAILED"):
		message = "No connection to the server. Check your internet."
	return {"ok": false, "error": code, "message": message}
