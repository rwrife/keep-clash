class_name ProfileStore
extends RefCounted
## Invalid/unknown saves are read-only for this run. Never replace their bytes.
## v1: {version:1, stars:int, settings?:Dictionary}. v2 adds selections/records.

const VERSION := 2
const MAX_BYTES := 262144
const MAX_STARS := 1000000000
const DEFAULT_PATH := "user://keep_clash.json"

var path: String
var data: Dictionary = defaults()
var error_message := ""
var write_blocked := false
var _source := ""
var _existed := false


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


static func default_settings() -> Dictionary:
	return {"master": 1.0, "music": 0.7, "sfx": 0.8, "reduced_motion": false,
		"high_contrast": false, "hud_scale": 1.0, "bindings": InputSetup.default_bindings()}


static func defaults() -> Dictionary:
	return {"version": VERSION, "stars": 0, "arena": "courtyard",
		"shield_skin": "classic", "keep_skin": "classic",
		"settings": default_settings(), "records": {"rounds": 0, "wins": 0, "best_stars": 0}}


func load_profile() -> bool:
	data = defaults()
	error_message = ""
	write_blocked = false
	_existed = FileAccess.file_exists(path)
	_source = ""
	if not _existed:
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _block("Cannot read save: %s" % error_string(FileAccess.get_open_error()))
	if file.get_length() > MAX_BYTES:
		return _block("Save is too large; original preserved.")
	_source = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(_source) != OK:
		return _block("Corrupt save; original preserved. Playing with temporary defaults.")
	var candidate: Variant = migrate(parser.data)
	if not candidate is Dictionary or not valid_profile(candidate):
		return _block("Unsupported or invalid save; original preserved. Playing with temporary defaults.")
	data = _integer_fields(candidate)
	return true


func save_profile() -> bool:
	if write_blocked:
		return false
	if not valid_profile(data):
		error_message = "Cannot save invalid profile."
		return false
	# Detect external changes and refuse to replace a file we have not loaded.
	if FileAccess.file_exists(path) != _existed:
		return _block("Save changed outside the game; original preserved.")
	if _existed:
		var current := FileAccess.open(path, FileAccess.READ)
		if current == null or current.get_as_text() != _source:
			return _block("Save changed or became unreadable; original preserved.")
		current.close()
	var text := JSON.stringify(data, "\t")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error_message = "Cannot write save: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	var check := FileAccess.open(temporary, FileAccess.READ)
	if write_error != OK or check == null or check.get_as_text() != text:
		error_message = "Save write failed; original preserved."
		return false
	check.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if err != OK:
		error_message = "Cannot replace save: %s. Original preserved." % error_string(err)
		return false
	_source = text
	_existed = true
	error_message = ""
	return true


func _block(message: String) -> bool:
	write_blocked = true
	error_message = message
	return false


static func migrate(raw: Variant) -> Variant:
	if not raw is Dictionary or not whole(raw.get("version"), 1, VERSION):
		return null
	var candidate: Dictionary = raw.duplicate(true)
	if int(candidate["version"]) == 1:
		if not whole(candidate.get("stars"), 0, MAX_STARS):
			return null
		var upgraded := defaults()
		upgraded["stars"] = int(candidate["stars"])
		if candidate.has("settings"):
			if not candidate["settings"] is Dictionary:
				return null
			for key in candidate["settings"]:
				if not upgraded["settings"].has(key):
					return null
				upgraded["settings"][key] = candidate["settings"][key]
		candidate = upgraded
	return candidate


static func _integer_fields(value: Dictionary) -> Dictionary:
	# JSON parses numbers as floats; restore integral fields for in-memory rules.
	var normalized := value.duplicate(true)
	for key in ["version", "stars"]:
		normalized[key] = int(normalized[key])
	for key in ["rounds", "wins", "best_stars"]:
		normalized["records"][key] = int(normalized["records"][key])
	for action in normalized["settings"]["bindings"]:
		for kind in ["keys", "buttons"]:
			var codes: Array = normalized["settings"]["bindings"][action][kind]
			for index in range(codes.size()):
				codes[index] = int(codes[index])
	return normalized


static func valid_profile(value: Dictionary) -> bool:
	if not whole(value.get("version"), VERSION, VERSION) or not whole(value.get("stars"), 0, MAX_STARS):
		return false
	var stars := int(value["stars"])
	if not value.get("arena") is String or not ArenaCatalog.arena_unlocked(value["arena"], stars):
		return false
	for kind in ["shield", "keep"]:
		var skin: Variant = value.get(kind + "_skin")
		if not skin is String or not ArenaCatalog.skin_unlocked(kind, skin, stars):
			return false
	if not value.get("settings") is Dictionary or not valid_settings(value["settings"]):
		return false
	var records: Variant = value.get("records")
	if not records is Dictionary:
		return false
	for key in ["rounds", "wins", "best_stars"]:
		if not whole(records.get(key), 0, 3 if key == "best_stars" else MAX_STARS):
			return false
	return records["wins"] <= records["rounds"]


static func valid_settings(value: Dictionary) -> bool:
	for key in ["master", "music", "sfx", "hud_scale"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
		if float(number) < (0.75 if key == "hud_scale" else 0.0) or float(number) > (1.5 if key == "hud_scale" else 1.0):
			return false
	for key in ["reduced_motion", "high_contrast"]:
		if not value.get(key) is bool:
			return false
	return value.get("bindings") is Dictionary and InputSetup.valid_bindings(value["bindings"])


static func whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high
