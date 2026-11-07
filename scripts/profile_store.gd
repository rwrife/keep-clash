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
var _source := PackedByteArray()
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
	_source = PackedByteArray()
	if not _existed:
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _block("Cannot read save: %s" % error_string(FileAccess.get_open_error()))
	if file.get_length() > MAX_BYTES:
		file.close()
		return _block("Save is too large; original preserved.")
	_source = file.get_buffer(file.get_length())
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _block("Cannot read complete save; original preserved.")
	var parser := JSON.new()
	var text := _source.get_string_from_utf8()
	if text.to_utf8_buffer() != _source or parser.parse(text) != OK:
		return _block("Corrupt save; original preserved. Playing with temporary defaults.")
	var candidate: Variant = migrate(parser.data)
	if not candidate is Dictionary or not valid_profile(candidate):
		return _block("Unsupported or invalid save; original preserved. Playing with temporary defaults.")
	data = _integer_fields(candidate)
	return true


func save_profile() -> bool:
	return _save_candidate(data)


func export_profile(destination: String) -> bool:
	var absolute := ProjectSettings.globalize_path(destination).simplify_path()
	var save_path := ProjectSettings.globalize_path(path).simplify_path()
	if destination.is_empty() or destination.begins_with("res://") or not absolute.is_absolute_path():
		return _fail("Choose a writable local backup path.")
	if absolute in [save_path, save_path + ".tmp"]:
		return _fail("Backup must not replace the active save or its temporary file.")
	if not valid_profile(data):
		return _fail("Cannot export invalid profile.")
	if not _atomic_write(absolute, JSON.stringify(data, "\t").to_utf8_buffer(), false):
		return false
	if not write_blocked:
		error_message = ""
	return true


func import_profile(source_path: String) -> bool:
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return _fail("Cannot read backup: %s. Current save preserved." % error_string(FileAccess.get_open_error()))
	var size := file.get_length()
	if size == 0 or size > MAX_BYTES:
		file.close()
		return _fail("Backup is empty or too large; current save preserved.")
	var bytes := file.get_buffer(size)
	var read_error := file.get_error()
	file.close()
	if read_error != OK or bytes.size() != size:
		return _fail("Cannot read complete backup; current save preserved.")
	var text := bytes.get_string_from_utf8()
	var parser := JSON.new()
	if text.to_utf8_buffer() != bytes or not _valid_json_tokens(text) or parser.parse(text) != OK:
		return _fail("Malformed JSON backup; current save preserved.")
	var candidate: Variant = migrate(parser.data)
	if not candidate is Dictionary or not valid_profile(candidate):
		return _fail("Unsupported or invalid backup schema; current save preserved.")
	var normalized := _integer_fields(candidate)
	if not _save_candidate(normalized):
		return false
	data = normalized
	return true


func _save_candidate(candidate: Dictionary) -> bool:
	if write_blocked:
		return false
	if not valid_profile(candidate):
		return _fail("Cannot save invalid profile.")
	var bytes := JSON.stringify(candidate, "\t").to_utf8_buffer()
	if not _atomic_write(path, bytes, true):
		return false
	_source = bytes
	_existed = true
	error_message = ""
	return true


func _save_unchanged() -> bool:
	# Detect external changes and refuse to replace a file we have not loaded.
	if FileAccess.file_exists(path) != _existed:
		return _block("Save changed outside the game; original preserved.")
	if _existed:
		var current := FileAccess.open(path, FileAccess.READ)
		if current == null:
			return _block("Save changed or became unreadable; original preserved.")
		if current.get_length() != _source.size():
			current.close()
			return _block("Save changed outside the game; original preserved.")
		var bytes := current.get_buffer(current.get_length())
		var read_error := current.get_error()
		current.close()
		if read_error != OK or bytes != _source:
			return _block("Save changed or became unreadable; original preserved.")
	return true


func _atomic_write(destination: String, bytes: PackedByteArray, guard_save: bool) -> bool:
	if guard_save and not _save_unchanged():
		return false
	var temporary := destination + ".tmp"
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(absolute_temporary):
		return _fail("Temporary file already exists; original preserved.")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("Cannot write file: %s. Original preserved." % error_string(FileAccess.get_open_error()))
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	var check := FileAccess.open(temporary, FileAccess.READ)
	var verified := false
	if check != null:
		verified = check.get_buffer(check.get_length()) == bytes and check.get_error() == OK
		check.close()
	if write_error != OK or not verified:
		return _discard_temporary(absolute_temporary, "File write failed; original preserved.")
	# Recheck after staging, immediately before the atomic rename.
	if guard_save and not _save_unchanged():
		return _discard_temporary(absolute_temporary, error_message)
	var err := DirAccess.rename_absolute(absolute_temporary, ProjectSettings.globalize_path(destination))
	if err != OK:
		return _discard_temporary(absolute_temporary, "Cannot replace file: %s. Original preserved." % error_string(err))
	return true


func _discard_temporary(temporary: String, message: String) -> bool:
	var err := DirAccess.remove_absolute(temporary)
	return _fail(message if err == OK else "%s Temporary cleanup failed: %s." % [message, error_string(err)])


func _fail(message: String) -> bool:
	error_message = message
	return false


func _block(message: String) -> bool:
	write_blocked = true
	return _fail(message)


static func _valid_json_tokens(text: String) -> bool:
	# Godot's JSON parser accepts trailing commas, raw controls and loose numbers.
	# Reject those extensions before treating a backup as versioned JSON.
	var token := RegEx.new()
	token.compile('"([^"\\\\\\x00-\\x1f]|\\\\(["\\\\/bfnrt]|u[0-9a-fA-F]{4}))*"|-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?|true|false|null|[{}\\[\\]:,]')
	var offset := 0
	var previous := ""
	while offset < text.length():
		if text[offset] in [" ", "\t", "\r", "\n"]:
			offset += 1
			continue
		var found := token.search(text, offset)
		if found == null or found.get_start() != offset:
			return false
		var value := found.get_string()
		if value in ["}", "]"] and previous == ",":
			return false
		# Separate numeric tokens cannot combine into a non-JSON number.
		if previous != "" and previous[0] in "-0123456789" and value[0] in "-0123456789":
			return false
		previous = value
		offset = found.get_end()
	return true


static func migrate(raw: Variant) -> Variant:
	if not raw is Dictionary or not whole(raw.get("version"), 1, VERSION):
		return null
	var candidate: Dictionary = raw.duplicate(true)
	if int(candidate["version"]) == 1:
		for key in candidate:
			if key not in ["version", "stars", "settings"]:
				return null
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
	if value.size() != defaults().size():
		return false
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
	if not records is Dictionary or records.size() != 3:
		return false
	for key in ["rounds", "wins", "best_stars"]:
		if not whole(records.get(key), 0, 3 if key == "best_stars" else MAX_STARS):
			return false
	return records["wins"] <= records["rounds"]


static func valid_settings(value: Dictionary) -> bool:
	if value.size() != default_settings().size():
		return false
	for key in ["master", "music", "sfx", "hud_scale"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
		if float(number) < (0.75 if key == "hud_scale" else 0.0) or float(number) > (1.5 if key == "hud_scale" else 1.0):
			return false
	for key in ["reduced_motion", "high_contrast"]:
		if not value.get(key) is bool:
			return false
	var bindings: Variant = value.get("bindings")
	if not bindings is Dictionary or bindings.size() != 3 or not InputSetup.valid_bindings(bindings):
		return false
	for action in bindings:
		if bindings[action].size() != 2:
			return false
	return true


static func whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high
