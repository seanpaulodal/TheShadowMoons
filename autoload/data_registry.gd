extends Node
## DataRegistry (autoload): loads the master JSON data once, validates it,
## and serves read-only lookups. Nothing else should parse these files.

const MAX_ENEMY_LEVEL := 2000

# Adjust "required" if your real field names differ.
# "aliases" (optional): if a row lacks a canonical field but has one of the
# alternate names listed, the value is copied into the canonical field.
const DATASETS := {
	"items": {
		"path": "res://data/TSM_Master_Data.json",
		"id_field": "item_id",
		"required": ["item_id", "item_name", "item_type", "item_rarity"],
	},
	"enemies": {
		"path": "res://data/TSM_Enemy_Data.json",
		"id_field": "enemy_id",
		"required": ["enemy_id", "enemy_name", "enemy_level", "max_health"],
	},
	"status_effects": {
		"path": "res://data/TSM_Status_Effects.json",
		"id_field": "effect_id",
		"required": ["effect_id", "name", "kind", "duration"],
	},
	"item_extra": {
		"path": "res://data/TSM_Item_Extra.json",
		"id_field": "item_id",
		"required": ["item_id", "equip_slot"],
	},
	"classes": {
		"path": "res://data/TSM_Class_Data.json",
		"id_field": "class_id",
		"required": ["class_id", "display_name", "start_attributes", "base_stats", "growth_stats"],
	},
	"achievements": {
		"path": "res://data/TSM_Achievements.json",
		"id_field": "id",
		"required": ["id", "name", "category", "completion_target"],
		"aliases": {
			"name": ["achievement_name"],
			"desc": ["achievement_desc"],
			"category": ["achievement_category"],
		},
	},
}

# Single-object settings files (not tables of rows).
const CONFIGS := {
	"stat_rules": {
		"path": "res://data/TSM_Stat_Rules.json",
		"required": ["attributes", "stats", "base_defaults", "growth_defaults"],
	},
	"combat_rules": {
		"path": "res://data/TSM_Combat_Rules.json",
		"required": ["hit_chance", "defense_constant", "max_reduction", "min_damage", "unarmed", "weapon_damage_stat"],
	},
	"element_rules": {
		"path": "res://data/TSM_Element_Rules.json",
		"required": ["multipliers", "elements", "aliases"],
	},
	"item_rules": {
		"path": "res://data/TSM_Item_Rules.json",
		"required": ["equipment_slots", "btype_to_stat", "consumable_btype", "inventory"],
	},
	"progression": {
		"path": "res://data/TSM_Progression.json",
		"required": ["max_level", "max_rebirth", "exp_base", "exp_exponent", "stat_points_per_level"],
	},
}

var loaded: bool = false
var _configs: Dictionary = {}         # config name -> Dictionary
var _tables: Dictionary = {}          # table name -> { id (String) -> row (Dictionary) }
var _errors: PackedStringArray = []
var _warnings: PackedStringArray = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	loaded = false
	_tables.clear()
	_configs.clear()
	_errors.clear()
	_warnings.clear()

	for table_name in DATASETS:
		_load_dataset(table_name, DATASETS[table_name])
	for config_name in CONFIGS:
		_load_config(config_name, CONFIGS[config_name])

	loaded = true
	var report := get_report()
	print("[DataRegistry] loaded: ", report["counts"],
			" | errors: ", _errors.size(), " | warnings: ", _warnings.size())
	for message in _errors:
		push_error("[DataRegistry] " + message)
	for message in _warnings:
		push_warning("[DataRegistry] " + message)
	EventBus.data_loaded.emit(report)


# ---------- Public lookups ----------

func get_item(id: Variant) -> Dictionary:
	return _get_row("items", id)

func get_enemy(id: Variant) -> Dictionary:
	return _get_row("enemies", id)

func get_achievement(id: Variant) -> Dictionary:
	return _get_row("achievements", id)

## Extra per-item settings that the item sheet does not have (equip slot, level and class limits).
func get_status_effect(id: Variant) -> Dictionary:
	return _get_row("status_effects", id)

func get_item_extra(id: Variant) -> Dictionary:
	return _get_row("item_extra", id)

func get_class_data(id: Variant) -> Dictionary:
	return _get_row("classes", id)

## A single-object settings file, e.g. "stat_rules" or "progression".
func get_config(config_name: String) -> Dictionary:
	return _configs.get(config_name, {})

func has_item(id: Variant) -> bool:
	return not _get_row("items", id).is_empty()

func get_ids(table_name: String) -> Array:
	if not _tables.has(table_name):
		return []
	return _tables[table_name].keys()

func get_report() -> Dictionary:
	var counts := {}
	for table_name in _tables:
		counts[table_name] = _tables[table_name].size()
	for config_name in _configs:
		counts[config_name] = 0 if _configs[config_name].is_empty() else 1
	return {
		"counts": counts,
		"errors": _errors.duplicate(),
		"warnings": _warnings.duplicate(),
	}


# ---------- Internals ----------

func _get_row(table_name: String, id: Variant) -> Dictionary:
	if not _tables.has(table_name):
		return {}
	var table: Dictionary = _tables[table_name]
	return table.get(str(id), {})


func _load_dataset(table_name: String, cfg: Dictionary) -> void:
	_tables[table_name] = {}
	var path: String = cfg["path"]
	var id_field: String = cfg["id_field"]

	if not FileAccess.file_exists(path):
		_errors.append("[%s] file not found: %s" % [table_name, path])
		return

	var json := JSON.new()
	var parse_result := json.parse(FileAccess.get_file_as_string(path))
	if parse_result != OK:
		_errors.append("[%s] JSON error in %s at line %d: %s" % [
				table_name, path, json.get_error_line(), json.get_error_message()])
		return

	var rows := _normalize(json.data, id_field)
	if rows.is_empty():
		_errors.append("[%s] no rows found in %s" % [table_name, path])
		return

	var table := {}
	var index := 0
	for row in rows:
		index += 1
		if not (row is Dictionary):
			_errors.append("[%s] row %d is not an object" % [table_name, index])
			continue

		# Skip completely blank rows (empty sheet rows are exported as nulls).
		var is_blank := true
		for value in row.values():
			if value != null and str(value).strip_edges() != "":
				is_blank = false
				break
		if is_blank:
			_warnings.append("[%s] row %d is completely blank (skipped). Delete it from the sheet." % [
					table_name, index])
			continue

		# Copy alternate column names into the canonical field (if configured).
		var aliases: Dictionary = cfg.get("aliases", {})
		for canonical in aliases:
			if not row.has(canonical):
				for alt in aliases[canonical]:
					if row.has(alt):
						row[canonical] = row[alt]
						break

		var missing: PackedStringArray = []
		for field in cfg["required"]:
			if not row.has(field) or row[field] == null or str(row[field]).strip_edges() == "":
				missing.append(field)
		if not missing.is_empty():
			# Find a readable name so the row is easy to locate in the sheet.
			var label: String = ""
			for key in ["enemy_name", "item_name", "name", "achievement_name"]:
				if row.has(key):
					label = str(row[key])
					break
			_errors.append("[%s] row %d (id: %s, name: %s) missing: %s | row has: %s" % [
					table_name, index, str(row.get(id_field, "?")), label,
					", ".join(missing), str(row.keys().slice(0, 8))])
			continue

		var id := str(row[id_field])
		if table.has(id):
			_errors.append("[%s] row %d has duplicate id: %s" % [table_name, index, id])
			continue
		table[id] = row

	_tables[table_name] = table
	if table_name == "enemies":
		_check_enemy_levels(table)


func _load_config(config_name: String, cfg: Dictionary) -> void:
	_configs[config_name] = {}
	var path: String = cfg["path"]
	if not FileAccess.file_exists(path):
		_errors.append("[%s] file not found: %s" % [config_name, path])
		return

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		_errors.append("[%s] JSON error in %s at line %d: %s" % [
				config_name, path, json.get_error_line(), json.get_error_message()])
		return
	if not (json.data is Dictionary):
		_errors.append("[%s] %s must contain one JSON object" % [config_name, path])
		return

	var missing: PackedStringArray = []
	for key in cfg["required"]:
		if not json.data.has(key):
			missing.append(key)
	if not missing.is_empty():
		_errors.append("[%s] missing keys: %s" % [config_name, ", ".join(missing)])
		return
	_configs[config_name] = json.data


## Accepts a list of rows, an object keyed by id, or {"anything": [rows]}.
## Accepts a list of rows, an object keyed by id, or either of those
## wrapped in single-key objects such as {"Master_Data": ...}.
func _normalize(data: Variant, id_field: String) -> Array:
	var node: Variant = data

	# Unwrap sheet-name wrappers such as {"Master_Data": {...}} (up to 3 levels).
	# Stops as soon as the node already looks like a table of rows.
	for _i in 3:
		if not (node is Dictionary) or _looks_like_rows(node):
			break
		var next: Variant = null
		for key in node:
			var candidate: Variant = node[key]
			if candidate is Array or (candidate is Dictionary and not candidate.has(id_field)):
				if next == null:
					next = candidate
					if node.size() > 1:
						_warnings.append("Several top-level keys found; using \"%s\"" % str(key))
		if next == null:
			break
		node = next

	var rows: Array = []
	if node is Array:
		rows = node
	elif node is Dictionary:
		for key in node:
			var row: Variant = node[key]
			if row is Dictionary:
				if not row.has(id_field):
					row = row.duplicate()
					row[id_field] = key
				rows.append(row)
	return rows


## True if the dictionary maps ids to flat row objects (rows hold plain
## values, not nested objects). Non-object entries are ignored.
func _looks_like_rows(d: Dictionary) -> bool:
	var found_row := false
	for key in d:
		var v: Variant = d[key]
		if v is Dictionary:
			for inner_value in v.values():
				if inner_value is Dictionary or inner_value is Array:
					return false
			found_row = true
	return found_row


func _check_enemy_levels(table: Dictionary) -> void:
	for id in table:
		var raw_level: Variant = table[id].get("enemy_level", 0)
		var level := 0
		if raw_level is int or raw_level is float:
			level = int(raw_level)
		elif raw_level is String and raw_level.is_valid_float():
			level = int(raw_level.to_float())
		else:
			_warnings.append("[enemies] %s has a non-numeric enemy_level: %s" % [id, str(raw_level)])
			continue
		if level > MAX_ENEMY_LEVEL and not str(id).to_lower().contains("dummy"):
			_warnings.append("[enemies] %s has level %d, above the %d cap" % [
					id, level, MAX_ENEMY_LEVEL])
