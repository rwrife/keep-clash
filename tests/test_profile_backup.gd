extends GutTest
## Isolated files only. Native dialog configuration is not device verification.

const MENU_SCENE: PackedScene = preload("res://scenes/menu.tscn")

class ChangedDuringWrite extends ProfileStore:
	var checks := 0
	var external := PackedByteArray()

	func _save_unchanged() -> bool:
		checks += 1
		if checks == 2:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return _block("Test could not simulate external modification.")
			file.store_buffer(external)
			file.close()
		return super._save_unchanged()

var _directory: String
var _path: String
var _backup: String
var _store: ProfileStore
var _previous_profile: ProfileStore
var _previous_settings: Dictionary


func before_each() -> void:
	_directory = "user://issue7_test_%d" % get_instance_id()
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(_directory)), OK)
	_path = _directory + "/profile.json"
	_backup = _directory + "/backup.json"
	_store = ProfileStore.new(_path)
	assert_true(_store.load_profile())
	_previous_profile = GameSession.profile
	_previous_settings = GameSession.settings.values.duplicate(true)
	GameSession.profile = _store
	GameSession.settings.apply(_store.data["settings"])


func after_each() -> void:
	GameSession.profile = _previous_profile
	GameSession.settings.apply(_previous_settings)
	for filename in [_path, _backup, _path + ".tmp", _backup + ".tmp"]:
		var absolute := ProjectSettings.globalize_path(filename)
		if FileAccess.file_exists(filename) or DirAccess.dir_exists_absolute(absolute):
			assert_eq(DirAccess.remove_absolute(absolute), OK)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory)), OK)


func _write(filename: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(filename, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_buffer(bytes)
		file.close()


func _read(filename: String) -> PackedByteArray:
	var file := FileAccess.open(filename, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _populated() -> Dictionary:
	var value := ProfileStore.defaults()
	value["stars"] = 12
	value["arena"] = "narrows"
	value["shield_skin"] = "aurora"
	value["keep_skin"] = "gilded"
	value["records"] = {"rounds": 9, "wins": 4, "best_stars": 3}
	value["settings"]["master"] = 0.0
	value["settings"]["music"] = 0.25
	value["settings"]["sfx"] = 0.5
	value["settings"]["reduced_motion"] = true
	value["settings"]["high_contrast"] = true
	value["settings"]["hud_scale"] = 1.25
	value["settings"]["bindings"]["shield_cw"]["keys"] = [KEY_L]
	value["settings"]["bindings"]["shield_cw"]["buttons"] = [JOY_BUTTON_DPAD_RIGHT]
	return value


func test_export_wipe_import_restores_full_profile_and_live_settings() -> void:
	var expected := _populated()
	_store.data = expected.duplicate(true)
	assert_true(_store.save_profile(), _store.error_message)
	var original := _read(_path)
	assert_true(_store.export_profile(ProjectSettings.globalize_path(_backup)), _store.error_message)
	assert_eq(_read(_path), original, "export never persists or modifies the active save")
	var exported := _read(_backup)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)), OK)
	assert_true(_store.load_profile())
	assert_eq(_store.data, ProfileStore.defaults())
	GameSession.settings.apply(_store.data["settings"])
	watch_signals(GameSession)
	assert_eq(GameSession.import_profile(ProjectSettings.globalize_path(_backup)), "")
	assert_signal_emitted(GameSession, "profile_changed")
	assert_eq(_store.data, expected)
	assert_eq(GameSession.settings.values, expected["settings"])
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.25, 0.0001)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	assert_true(InputMap.event_is_action(key, InputSetup.ACTION_CW))
	assert_true(_store.data["stars"] is int)
	assert_true(_store.data["records"]["wins"] is int)
	assert_true(_store.data["settings"]["bindings"]["shield_cw"]["keys"][0] is int)
	var restarted := ProfileStore.new(_path)
	assert_true(restarted.load_profile(), restarted.error_message)
	assert_eq(restarted.data, expected)
	assert_eq(_read(_backup), exported, "import is read-only for the backup")
	assert_false(FileAccess.file_exists(_path + ".tmp"))
	assert_false(FileAccess.file_exists(_backup + ".tmp"))


func test_export_copies_unsaved_active_progress_without_mutating_save() -> void:
	assert_true(_store.save_profile())
	var original := _read(_path)
	_store.data = _populated()
	var active := _store.data.duplicate(true)
	assert_true(_store.export_profile(_backup), _store.error_message)
	assert_eq(_store.data, active)
	assert_eq(_read(_path), original)
	var exported := ProfileStore.new(_backup)
	assert_true(exported.load_profile())
	assert_eq(exported.data, active)
	_store.data["stars"] = 15
	assert_true(_store.export_profile(_backup), "a user-selected existing backup can be atomically replaced")
	assert_true(exported.load_profile())
	assert_eq(exported.data["stars"], 15)


func test_malformed_and_unsupported_imports_preserve_bytes_and_runtime() -> void:
	var original := ("\r\n  " + JSON.stringify(_populated(), "  ") + "\r\n").to_utf8_buffer()
	_write(_path, original)
	assert_true(_store.load_profile())
	GameSession.settings.apply(_store.data["settings"])
	_store.data["stars"] = 14
	var active := _store.data.duplicate(true)
	var runtime := GameSession.settings.values.duplicate(true)
	var invalid: Array[String] = ["", "{bad", "null", "[]", "{}",
		'{"version":99,"stars":9}', '{"version":1,"stars":-1}',
		'{"version":1,"stars":1.5}', '{"version":1,"stars":9,"ignored":true}',
		'{"version":1,"stars":01}', '{"version":1,"stars":+1}',
		'{"version":1,"stars":1,}', '{"version":1,"stars":1,"settings":{"master":.5}}',
		'{"version":1,"stars":1,"settings":{"master":0.5,"unused":"raw\ncontrol"}}',
		" ".repeat(ProfileStore.MAX_BYTES + 1)]
	for missing_key in ["settings", "records", "arena", "shield_skin", "keep_skin"]:
		var missing := _populated()
		missing.erase(missing_key)
		invalid.append(JSON.stringify(missing))
	var cases: Array[Dictionary] = []
	var value := _populated()
	value["settings"]["master"] = 2
	cases.append(value)
	value = _populated()
	value["settings"]["reduced_motion"] = "true"
	cases.append(value)
	value = _populated()
	value["records"]["wins"] = 10
	cases.append(value)
	value = _populated()
	value["stars"] = 0
	cases.append(value)
	value = _populated()
	value["settings"]["bindings"]["shield_cw"]["keys"] = [KEY_A]
	cases.append(value)
	value = _populated()
	value["settings"]["bindings"]["unknown"] = null
	cases.append(value)
	value = _populated()
	value["settings"]["bindings"]["pause"]["unknown"] = true
	cases.append(value)
	value = _populated()
	value["records"]["unknown"] = true
	cases.append(value)
	value = _populated()
	value["unknown"] = true
	cases.append(value)
	for candidate in cases:
		invalid.append(JSON.stringify(candidate))
	watch_signals(GameSession)
	for text in invalid:
		_write(_backup, text.to_utf8_buffer())
		assert_ne(GameSession.import_profile(_backup), "")
		assert_eq(_read(_path), original, "failed import preserves exact bytes, including whitespace")
		assert_eq(_store.data, active, "failed import preserves unsaved active progress")
		assert_eq(GameSession.settings.values, runtime)
		assert_false(_store.write_blocked, "bad input alone must not block subsequent valid saves")
		assert_false(FileAccess.file_exists(_path + ".tmp"), "validation precedes all save writes")
	assert_signal_not_emitted(GameSession, "profile_changed")
	_write(_backup, JSON.stringify(_populated()).to_utf8_buffer())
	assert_eq(GameSession.import_profile(_backup), "", "a valid retry succeeds after rejected input")


func test_supported_version_one_import_migrates_and_preserves_backup() -> void:
	var legacy := '{"version":1,"stars":7,"settings":{"master":0.4,"high_contrast":true}}'.to_utf8_buffer()
	_write(_backup, legacy)
	assert_eq(GameSession.import_profile(_backup), "")
	assert_eq(_store.data["version"], ProfileStore.VERSION)
	assert_eq(_store.data["stars"], 7)
	assert_eq(_store.data["records"], ProfileStore.defaults()["records"])
	assert_eq(GameSession.settings.values["master"], 0.4)
	assert_true(GameSession.settings.values["high_contrast"])
	assert_eq(_read(_backup), legacy)
	var restarted := ProfileStore.new(_path)
	assert_true(restarted.load_profile())
	assert_eq(restarted.data, _store.data)


func test_missing_backup_and_staging_failures_preserve_existing_save() -> void:
	assert_true(_store.save_profile())
	var original := _read(_path)
	var active := _store.data.duplicate(true)
	var runtime := GameSession.settings.values.duplicate(true)
	assert_ne(GameSession.import_profile(_backup), "")
	assert_eq(_read(_path), original)
	_write(_backup, JSON.stringify(_populated()).to_utf8_buffer())
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(_path + ".tmp")), OK)
	assert_ne(GameSession.import_profile(_backup), "")
	assert_eq(_read(_path), original)
	assert_eq(_store.data, active)
	assert_eq(GameSession.settings.values, runtime)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + ".tmp")), OK)
	var other_file := "do not truncate another writer's temporary file".to_utf8_buffer()
	_write(_path + ".tmp", other_file)
	assert_ne(GameSession.import_profile(_backup), "")
	assert_eq(_read(_path), original)
	assert_eq(_read(_path + ".tmp"), other_file)
	assert_eq(_store.data, active)


func test_valid_import_cannot_replace_a_read_only_corrupt_save() -> void:
	var original := "unrecoverable current save\r\n".to_utf8_buffer()
	_write(_path, original)
	assert_false(_store.load_profile())
	_write(_backup, JSON.stringify(_populated()).to_utf8_buffer())
	assert_ne(GameSession.import_profile(_backup), "")
	assert_true(_store.write_blocked)
	assert_eq(_read(_path), original)
	assert_eq(_store.data, ProfileStore.defaults())
	assert_eq(GameSession.settings.values, ProfileStore.default_settings())
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_import_guard_detects_changed_created_and_deleted_save() -> void:
	_write(_backup, JSON.stringify(_populated()).to_utf8_buffer())
	for kind in ["changed", "created", "deleted"]:
		if FileAccess.file_exists(_path):
			assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)), OK)
		assert_true(_store.load_profile())
		if kind != "created":
			assert_true(_store.save_profile())
		var active := _store.data.duplicate(true)
		var external := PackedByteArray([255, 0, 254, 13, 10])
		if kind == "deleted":
			assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)), OK)
		else:
			_write(_path, external)
		assert_ne(GameSession.import_profile(_backup), "")
		assert_true(_store.write_blocked)
		if kind == "deleted":
			assert_false(FileAccess.file_exists(_path), "import must not recreate an externally deleted save")
		else:
			assert_eq(_read(_path), external, "guard compares bytes, without decoding external content")
		assert_eq(_store.data, active)
		assert_eq(GameSession.settings.values, ProfileStore.default_settings())
		assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_import_rechecks_external_changes_after_staging() -> void:
	assert_true(_store.save_profile())
	var guarded := ChangedDuringWrite.new(_path)
	assert_true(guarded.load_profile())
	guarded.external = "external change during staging\r\n".to_utf8_buffer()
	GameSession.profile = guarded
	_write(_backup, JSON.stringify(_populated()).to_utf8_buffer())
	assert_ne(GameSession.import_profile(_backup), "")
	assert_eq(guarded.checks, 2)
	assert_true(guarded.write_blocked)
	assert_eq(_read(_path), guarded.external)
	assert_eq(guarded.data, ProfileStore.defaults())
	assert_eq(GameSession.settings.values, ProfileStore.default_settings())
	assert_false(FileAccess.file_exists(_path + ".tmp"), "failed late guard cleans only its own staging file")


func test_export_rejects_live_save_and_preserves_existing_backup_on_failure() -> void:
	assert_true(_store.save_profile())
	var original := _read(_path)
	assert_false(_store.export_profile(ProjectSettings.globalize_path(_path)))
	assert_false(_store.export_profile(_path + ".tmp"))
	assert_eq(_read(_path), original)
	var backup_bytes := "existing backup must survive a failed export".to_utf8_buffer()
	_write(_backup, backup_bytes)
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(_backup + ".tmp")), OK)
	assert_false(_store.export_profile(_backup))
	assert_ne(_store.error_message, "")
	assert_eq(_read(_backup), backup_bytes)
	assert_eq(_read(_path), original)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_backup + ".tmp")), OK)
	_store.data["stars"] = -1
	assert_false(_store.export_profile(_backup))
	assert_eq(_read(_backup), backup_bytes)
	assert_eq(_read(_path), original)


func test_menu_backup_configuration_callbacks_and_cancel() -> void:
	var menu: Control = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	assert_true(menu._backup_dialog.use_native_dialog)
	assert_eq(menu._backup_dialog.access, FileDialog.ACCESS_FILESYSTEM)
	var button_texts: Array[String] = []
	for button in menu.find_children("*", "Button", true, false):
		button_texts.append(button.text)
	assert_has(button_texts, "EXPORT BACKUP")
	assert_has(button_texts, "IMPORT BACKUP (REPLACE PROFILE)")
	_store.data = _populated()
	assert_true(_store.save_profile())
	var original := _read(_path)
	menu._backup_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	menu._backup_dialog.file_selected.emit(ProjectSettings.globalize_path(_backup))
	assert_true(menu._message.begins_with("Backup exported"))
	assert_eq(_read(_path), original)
	_store.data = ProfileStore.defaults()
	assert_true(_store.save_profile())
	menu._backup_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	menu._backup_dialog.file_selected.emit(ProjectSettings.globalize_path(_backup))
	assert_eq(_store.data, _populated())
	assert_eq(GameSession.settings.values, _populated()["settings"])
	assert_eq(menu._message, "Backup imported; settings and progress restored.")
	original = _read(_path)
	_write(_backup, "{bad".to_utf8_buffer())
	menu._backup_dialog.file_selected.emit(ProjectSettings.globalize_path(_backup))
	assert_eq(menu._message, _store.error_message)
	assert_eq(_read(_path), original)
	menu._backup_open = true
	menu._backup_dialog.canceled.emit()
	assert_false(menu._backup_open)
	assert_eq(_read(_path), original)
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		menu._show_backup(false)
		assert_false(menu._backup_open)
		assert_true(menu._message.begins_with("Native file dialogs are unavailable"))
		assert_eq(_read(_path), original)


func test_android_export_presets_require_no_network_permissions() -> void:
	var config := ConfigFile.new()
	assert_eq(config.load("res://export_presets.cfg"), OK)
	var android_presets := 0
	for section in config.get_sections():
		if config.get_value(section, "platform", "") != "Android":
			continue
		android_presets += 1
		var options := section + ".options"
		assert_true(config.has_section(options))
		assert_false(config.get_value(options, "permissions/internet", true), "internet must be explicitly disabled")
		for key in config.get_section_keys(options):
			if not key.begins_with("permissions/"):
				continue
			if key == "permissions/custom_permissions":
				for permission in config.get_value(options, key):
					var name := String(permission).to_lower()
					assert_false("internet" in name or "network" in name or "wifi" in name, permission)
			elif "internet" in key or "network" in key or "wifi" in key:
				assert_false(config.get_value(options, key), key)
	assert_gt(android_presets, 0, "privacy check must inspect at least one Android preset")
