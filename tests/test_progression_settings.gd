extends GutTest
## Files are isolated from the real profile. Notification tests are synthetic,
## not Android/iOS device verification.

const ROUND_SCENE: PackedScene = preload("res://scenes/round.tscn")

var _path: String
var _store: ProfileStore
var _previous_profile: ProfileStore
var _previous_settings: Dictionary
var _previous_seats: Array[Dictionary]


func before_each() -> void:
	_path = "user://issue5_test_%d.json" % get_instance_id()
	_remove_test_files()
	_store = ProfileStore.new(_path)
	assert_true(_store.load_profile())
	_previous_profile = GameSession.profile
	_previous_settings = GameSession.settings.values.duplicate(true)
	_previous_seats = SeatRouting.duplicate_seats(GameSession.seats)
	GameSession.profile = _store
	GameSession.seats = SeatRouting.make_solo_seats(0, false)
	GameSession.settings.apply(_store.data["settings"])


func after_each() -> void:
	GameSession.profile = _previous_profile
	GameSession.seats = _previous_seats
	GameSession.settings.apply(_previous_settings)
	_remove_test_files()


func _remove_test_files() -> void:
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(_path + suffix):
			assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix)), OK)


func _write(text: String) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(text)
		file.close()


func _read() -> String:
	var file := FileAccess.open(_path, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return ""
	return file.get_as_text()


func _arena(id: String = "courtyard") -> Node3D:
	_store.data["stars"] = 20
	_store.data["arena"] = id
	var arena: Node3D = ROUND_SCENE.instantiate()
	add_child_autofree(arena)
	arena.set_process(false)
	return arena


func test_new_profile_and_full_json_roundtrip() -> void:
	assert_false(FileAccess.file_exists(_path), "load must not create/replace a save")
	_store.data["stars"] = 12
	_store.data["arena"] = "narrows"
	_store.data["shield_skin"] = "aurora"
	_store.data["keep_skin"] = "gilded"
	_store.data["records"] = {"rounds": 9, "wins": 4, "best_stars": 3}
	_store.data["settings"]["master"] = 0.35
	_store.data["settings"]["music"] = 0.2
	_store.data["settings"]["sfx"] = 0.6
	_store.data["settings"]["reduced_motion"] = true
	_store.data["settings"]["high_contrast"] = true
	_store.data["settings"]["hud_scale"] = 1.25
	_store.data["settings"]["bindings"]["shield_cw"]["keys"] = [KEY_L]
	assert_true(_store.save_profile(), _store.error_message)
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile(), reader.error_message)
	assert_eq(reader.data, _store.data)
	assert_eq(int(JSON.parse_string(_read())["version"]), ProfileStore.VERSION)
	assert_false(FileAccess.file_exists(_path + ".tmp"), "atomic replacement consumes temporary file")


func test_repeated_saves_replace_only_the_loaded_profile() -> void:
	assert_true(_store.save_profile())
	_store.data["stars"] = 4
	assert_true(_store.save_profile())
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	assert_eq(int(reader.data["stars"]), 4)


func test_version_one_migrates_in_memory_without_overwriting_source() -> void:
	var legacy := "{\"version\":1,\"stars\":7,\"settings\":{\"master\":0.4,\"reduced_motion\":true}}"
	_write(legacy)
	assert_true(_store.load_profile())
	assert_eq(int(_store.data["version"]), 2)
	assert_eq(int(_store.data["stars"]), 7)
	assert_eq(_store.data["settings"]["master"], 0.4)
	assert_true(_store.data["settings"]["reduced_motion"])
	assert_eq(_store.data["settings"]["hud_scale"], 1.0)
	assert_eq(_read(), legacy, "loading a migration is non-destructive")
	assert_true(_store.save_profile(), "a validated migration can explicitly persist")
	assert_eq(int(JSON.parse_string(_read())["version"]), 2)


func test_minimal_version_one_gets_complete_defaults() -> void:
	_write("{\"version\":1,\"stars\":3}")
	assert_true(_store.load_profile())
	assert_true(ProfileStore.valid_profile(_store.data))
	assert_eq(_store.data["arena"], "courtyard")
	assert_eq(_store.data["settings"]["bindings"], InputSetup.default_bindings())


func test_corrupt_and_unsupported_profiles_are_preserved_byte_for_byte() -> void:
	var invalid := ["", "{bad", "null", "[]", "{\"version\":99,\"stars\":9}",
		"{\"version\":0,\"stars\":9}", "{\"version\":1,\"stars\":-1}",
		"{\"version\":1,\"stars\":1.5}", "{\"version\":1,\"stars\":\"9\"}",
		"{\"version\":1,\"stars\":9,\"settings\":{\"master\":\"loud\"}}"]
	for text in invalid:
		_write(text)
		assert_false(_store.load_profile(), text)
		assert_true(_store.write_blocked)
		assert_ne(_store.error_message, "")
		assert_eq(_store.data, ProfileStore.defaults())
		_store.data["stars"] = 10
		assert_false(_store.save_profile())
		assert_eq(_read(), text)


func test_invalid_current_schema_cannot_erase_or_unlock_content() -> void:
	var cases: Array[Dictionary] = []
	for key in ["version", "stars", "settings", "records", "arena", "shield_skin", "keep_skin"]:
		var missing := ProfileStore.defaults()
		missing.erase(key)
		cases.append(missing)
	var locked := ProfileStore.defaults()
	locked["arena"] = "diamond"
	cases.append(locked)
	var wrong_bool := ProfileStore.defaults()
	wrong_bool["settings"]["high_contrast"] = 1
	cases.append(wrong_bool)
	var invalid_records := ProfileStore.defaults()
	invalid_records["records"]["wins"] = 2
	cases.append(invalid_records)
	for value in cases:
		var text := JSON.stringify(value)
		_write(text)
		assert_false(_store.load_profile())
		assert_false(_store.save_profile())
		assert_eq(_read(), text)


func test_oversized_save_is_preserved() -> void:
	var text := " ".repeat(ProfileStore.MAX_BYTES + 1)
	_write(text)
	assert_false(_store.load_profile())
	assert_false(_store.save_profile())
	assert_eq(_read(), text)


func test_external_modification_is_not_overwritten() -> void:
	assert_true(_store.save_profile())
	var external := "{\"version\":99,\"keep_me\":true}"
	_write(external)
	assert_false(_store.save_profile())
	assert_true(_store.write_blocked)
	assert_eq(_read(), external)


func test_failed_write_retains_original_save_and_reports_error() -> void:
	assert_true(_store.save_profile())
	var original := _read()
	var temporary := ProjectSettings.globalize_path(_path + ".tmp")
	assert_eq(DirAccess.make_dir_absolute(temporary), OK)
	_store.data["stars"] = 1
	assert_false(_store.save_profile(), "a directory cannot be opened as the temporary file")
	assert_ne(_store.error_message, "")
	assert_eq(_read(), original)
	assert_eq(DirAccess.remove_absolute(temporary), OK)


func test_settings_validation_rejects_bad_ranges_types_and_bindings() -> void:
	for key in ["master", "music", "sfx", "hud_scale"]:
		for value in [-1, 2, "0.5", null, INF, NAN]:
			var settings := ProfileStore.default_settings()
			settings[key] = value
			assert_false(ProfileStore.valid_settings(settings), "%s=%s" % [key, value])
	var settings := ProfileStore.default_settings()
	settings["bindings"]["shield_cw"]["keys"] = [KEY_A]
	assert_false(ProfileStore.valid_settings(settings), "conflicting physical keys")
	settings = ProfileStore.default_settings()
	settings["bindings"]["pause"]["buttons"] = [JOY_BUTTON_MAX]
	assert_false(ProfileStore.valid_settings(settings))
	settings = ProfileStore.default_settings()
	settings["bindings"]["shield_cw"]["keys"] = []
	assert_false(ProfileStore.valid_settings(settings))


func test_arena_unlock_thresholds_and_cosmetic_thresholds() -> void:
	for id in ArenaCatalog.IDS:
		var threshold := int(ArenaCatalog.ARENAS[id]["stars"])
		assert_true(ArenaCatalog.arena_unlocked(id, threshold))
		assert_false(ArenaCatalog.arena_unlocked(id, threshold - 1))
	assert_false(ArenaCatalog.arena_unlocked("unknown", 999))
	assert_false(ArenaCatalog.skin_unlocked("shield", "aurora", 2))
	assert_true(ArenaCatalog.skin_unlocked("shield", "aurora", 3))
	assert_false(ArenaCatalog.skin_unlocked("keep", "gilded", 5))
	assert_true(ArenaCatalog.skin_unlocked("keep", "gilded", 6))
	assert_false(ArenaCatalog.skin_unlocked("keep", "unknown", 999))


func test_locked_selection_is_refused_and_unlocked_selection_persists() -> void:
	GameSession.select_item("arena", "narrows")
	GameSession.select_item("shield", "aurora")
	assert_eq(_store.data["arena"], "courtyard")
	assert_eq(_store.data["shield_skin"], "classic")
	_store.data["stars"] = 8
	GameSession.select_item("arena", "narrows")
	GameSession.select_item("shield", "aurora")
	GameSession.select_item("keep", "gilded")
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	assert_eq(reader.data["arena"], "narrows")
	assert_eq(reader.data["shield_skin"], "aurora")
	assert_eq(reader.data["keep_skin"], "gilded")
	assert_eq(int(reader.data["stars"]), 8, "unlock thresholds do not spend stars")


func test_each_arena_uses_distinct_collision_layout_and_rules() -> void:
	var layouts: Array = []
	var speeds: Array = []
	for id in ArenaCatalog.IDS:
		var controller := RoundController.new(SeatRouting.make_default_seats(), 55, id)
		var definition: Dictionary = ArenaCatalog.ARENAS[id]
		assert_eq(controller.rules.positions, definition["positions"])
		assert_false(layouts.has(controller.rules.positions))
		layouts.append(controller.rules.positions)
		controller.rules.serve(0.0)
		assert_almost_eq(controller.rules.ball_velocity.length(), definition["speed"], 0.0001)
		assert_false(speeds.has(controller.rules.serve_speed))
		speeds.append(controller.rules.serve_speed)
		assert_eq(controller.time_limit, definition["seconds"])
		assert_eq(controller.speed_gain, definition["gain"])
		controller.rules.ball_position = controller.bounds + Vector2.ONE
		controller.rules.ball_velocity = Vector2(10, 10)
		controller._apply_rails()
		assert_eq(controller.rules.ball_position, controller.bounds)
		assert_lt(controller.rules.ball_velocity.x, 0.0)
		assert_lt(controller.rules.ball_velocity.y, 0.0)
		var center: Vector2 = controller.rules.positions[0]
		controller.rules.set_shield_angle(0, -PI / 2)
		controller.rules.ball_position = center + Vector2(0, 5)
		controller.rules.ball_velocity = Vector2(0, -1000)
		var events := controller.rules.step(RoundController.TICK)
		assert_false(events.is_empty(), "the collision sweep must use the chosen layout")
		if not events.is_empty():
			assert_eq(events[0]["kind"], "wall")
			assert_eq(events[0]["seat"], 0)
		controller.rematch()
		assert_eq(controller.arena_id, id)
		assert_eq(controller.rules.positions, definition["positions"])


func test_each_arena_remains_seed_deterministic_with_interruption() -> void:
	for id in ArenaCatalog.IDS:
		var first := RoundController.new(SeatRouting.make_default_seats(), 1234, id)
		var second := RoundController.new(SeatRouting.make_default_seats(), 1234, id)
		for tick in range(1200):
			first.tick()
			second.tick()
			if tick == 500:
				first.interrupt()
				assert_eq(first.advance(30.0), 0)
				first.set_paused(false)
		assert_eq(first.rules.ball_position, second.rules.ball_position)
		assert_eq(first.rules.ball_velocity, second.rules.ball_velocity)
		assert_eq(first.rules.keeps, second.rules.keeps)
		assert_eq(first.targets, second.targets)


func test_arena_scene_renders_selected_layout_bounds_and_floor() -> void:
	for id in ArenaCatalog.IDS:
		var arena := _arena(id)
		for seat in range(4):
			var center: Vector2 = arena.controller.rules.positions[seat]
			assert_eq(arena._shield_nodes[seat].get_parent().position, Vector3(center.x, 0, center.y))
		assert_eq(arena._floor_mat.albedo_color, ArenaCatalog.ARENAS[id]["floor"])
		arena.free()


func test_stars_awarded_once_only_for_a_human_winner() -> void:
	var controller := RoundController.new(SeatRouting.make_solo_seats(1, false), 55)
	controller.state = RoundController.State.ROUND_OVER
	controller.result = {"winner": 2, "stars": [0, 0, 3, 0], "timed_out": false, "elapsed": 4.0}
	GameSession.record_round(controller)
	GameSession.record_round(controller)
	assert_eq(_store.data["stars"], 3)
	assert_eq(_store.data["records"], {"rounds": 1, "wins": 1, "best_stars": 3})
	controller.rematch()
	controller.state = RoundController.State.ROUND_OVER
	controller.result = {"winner": 1, "stars": [0, 3, 0, 0]}
	GameSession.record_round(controller)
	assert_eq(_store.data["stars"], 3, "bot wins do not farm local stars")
	assert_eq(_store.data["records"]["rounds"], 2)
	controller.rematch()
	controller.state = RoundController.State.ROUND_OVER
	controller.result = {"winner": -1, "stars": [0, 0, 0, 0]}
	GameSession.record_round(controller)
	assert_eq(_store.data["stars"], 3, "draws earn nothing")
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	assert_eq(reader.data["records"], {"rounds": 3, "wins": 1, "best_stars": 3})


func test_scene_finish_awards_stars_and_rematch_does_not_duplicate() -> void:
	var arena := _arena()
	arena.controller.rules.winner = 2
	arena.controller.rules.keeps[2]["deflections"] = 3
	arena.controller._finish()
	assert_eq(_store.data["stars"], 23)
	assert_true(arena._overlay.visible)
	arena._refresh_overlay()
	assert_eq(_store.data["stars"], 23)
	arena._rematch()
	assert_false(arena._overlay.visible)
	assert_eq(_store.data["stars"], 23)


func test_cosmetics_change_visible_resources_not_collision_rules() -> void:
	var classic := _arena()
	_store.data["shield_skin"] = "aurora"
	_store.data["keep_skin"] = "gilded"
	var skinned := _arena()
	var classic_shield: MeshInstance3D = classic._shield_nodes[2].get_child(0)
	var skinned_shield: MeshInstance3D = skinned._shield_nodes[2].get_child(0)
	assert_eq(classic_shield.mesh, skinned_shield.mesh, "cosmetics share the imported shield")
	assert_eq(classic_shield.scale, Vector3.ONE)
	assert_almost_eq(skinned_shield.scale.y, 1.0 / 0.7, 0.0001)
	assert_ne(classic._core_mats[2].albedo_color, skinned._core_mats[2].albedo_color)
	assert_ne(classic._shield_mats[2].albedo_color, skinned._shield_mats[2].albedo_color)
	assert_eq(classic.controller.rules.positions, skinned.controller.rules.positions)
	assert_eq(classic.controller.rules.keeps, skinned.controller.rules.keeps)
	assert_eq(classic.controller.rules.serve_speed, skinned.controller.rules.serve_speed)


func test_audio_settings_apply_live_and_reload_on_restart() -> void:
	var arena := _arena()
	var settings := ProfileStore.default_settings()
	settings["master"] = 0.0
	settings["music"] = 0.25
	settings["sfx"] = 0.5
	assert_eq(GameSession.update_settings(settings), "")
	assert_eq(arena._impact_audio.bus, &"SFX")
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.25, 0.0001)
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.5, 0.0001)
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	GameSession.settings.apply(ProfileStore.default_settings())
	var restarted := SettingsRuntime.new()
	restarted.apply(reader.data["settings"])
	assert_eq(restarted.values, settings)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))


func test_music_is_a_local_loop_routed_separately_from_sfx() -> void:
	assert_eq(GameSession._music_player.bus, &"Music")
	var stream: AudioStreamWAV = GameSession._music_player.stream
	assert_not_null(stream)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_almost_eq(stream.get_length(), 4.0, 0.0001)
	assert_eq(stream.loop_begin, 0)
	assert_eq(stream.loop_end, 22050 * 4)
	assert_eq(stream.data.decode_s16(0), 0)
	assert_almost_eq(stream.data.decode_s16(stream.data.size() - 2), 0, 1)
	assert_ne(AudioServer.get_bus_index("Music"), AudioServer.get_bus_index("SFX"))


func test_accessibility_applies_live_and_survives_reload() -> void:
	var arena := _arena()
	arena._on_match_event({"kind": "wall", "seat": 0, "wall": 0})
	assert_gt(arena._shake_remaining, 0.0)
	var settings := ProfileStore.default_settings()
	settings["reduced_motion"] = true
	settings["high_contrast"] = true
	settings["hud_scale"] = 1.5
	assert_eq(GameSession.update_settings(settings), "")
	assert_eq(arena._shake_remaining, 0.0)
	assert_eq(arena._camera.position, arena._camera_rest_position)
	for burst in arena._impact_pool:
		assert_false(burst.emitting)
	arena._on_match_event({"kind": "wall", "seat": 0, "wall": 0})
	assert_eq(arena._next_impact, 0, "reduced motion suppresses new particles and shake")
	assert_eq(arena._impact_audio.stream, arena._wall_tone, "reduced motion must not disable SFX")
	assert_eq(arena._floor_mat.albedo_color, Color("080c14"))
	assert_eq(arena._seat_labels[0].get_theme_color("font_color"), Color.WHITE)
	var expected_size := roundi((13.0 if arena.get_viewport().get_visible_rect().size.x < 960.0 else 16.0) * 1.5)
	assert_eq(arena._seat_labels[0].get_theme_font_size("font_size"), expected_size)
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	GameSession.settings.apply(ProfileStore.default_settings())
	GameSession.settings.apply(reader.data["settings"])
	assert_true(arena._reduced_motion())
	assert_eq(arena._seat_labels[0].get_theme_font_size("font_size"), expected_size)
	GameSession.update_settings(ProfileStore.default_settings())
	assert_eq(arena._floor_mat.albedo_color, ArenaCatalog.ARENAS["courtyard"]["floor"])
	assert_eq(arena._shield_mats[0].albedo_color, ArenaLook.shield_material(0).albedo_color)


func test_remapping_applies_live_persists_and_rejects_conflicts() -> void:
	var settings := ProfileStore.default_settings()
	settings["bindings"]["shield_cw"]["keys"] = [KEY_L]
	settings["bindings"]["shield_cw"]["buttons"] = [JOY_BUTTON_DPAD_RIGHT]
	assert_eq(GameSession.update_settings(settings), "")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	assert_true(InputMap.event_is_action(key, InputSetup.ACTION_CW))
	key.physical_keycode = KEY_D
	assert_false(InputMap.event_is_action(key, InputSetup.ACTION_CW))
	var pad := InputEventJoypadButton.new()
	# InputMap.event_is_action compares event device too; runtime polls mapped
	# button per claimed device through InputSetup.device_strength.
	pad.device = 0
	pad.pressed = true
	pad.button_index = JOY_BUTTON_DPAD_RIGHT
	assert_true(InputMap.event_is_action(pad, InputSetup.ACTION_CW))
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	GameSession.settings.apply(ProfileStore.default_settings())
	var restarted := SettingsRuntime.new()
	restarted.apply(reader.data["settings"])
	assert_true(InputMap.event_is_action(pad, InputSetup.ACTION_CW))
	var before := _read()
	settings["bindings"]["shield_ccw"]["keys"] = [KEY_L]
	assert_ne(GameSession.update_settings(settings), "")
	assert_eq(_read(), before)


func test_settings_panel_captures_keyboard_and_gamepad_and_saves() -> void:
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	panel._capture_action = "shield_cw"
	panel._capture_kind = "keys"
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_L
	panel._input(key)
	assert_eq(GameSession.settings.values["bindings"]["shield_cw"]["keys"], [KEY_L])
	panel._capture_action = "pause"
	panel._capture_kind = "buttons"
	var button := InputEventJoypadButton.new()
	button.pressed = true
	button.button_index = JOY_BUTTON_BACK
	panel._input(button)
	assert_eq(GameSession.settings.values["bindings"]["pause"]["buttons"], [JOY_BUTTON_BACK])
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	assert_eq(reader.data["settings"], GameSession.settings.values)


func test_corrupt_save_still_allows_temporary_live_settings_with_warning() -> void:
	var corrupt := "unrecoverable original"
	_write(corrupt)
	assert_false(_store.load_profile())
	var settings := ProfileStore.default_settings()
	settings["high_contrast"] = true
	assert_ne(GameSession.update_settings(settings), "")
	assert_true(GameSession.settings.values["high_contrast"])
	assert_eq(_read(), corrupt)


func test_settings_ui_slider_and_toggle_apply_and_save_live() -> void:
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	var slider: HSlider = panel.find_child("master", true, false)
	var toggle: CheckButton = panel.find_child("high_contrast", true, false)
	assert_not_null(slider)
	assert_not_null(toggle)
	slider.value = 0.35
	toggle.button_pressed = true
	assert_almost_eq(GameSession.settings.values["master"], 0.35, 0.0001)
	assert_true(GameSession.settings.values["high_contrast"])
	assert_eq(panel.theme.get_color("font_color", "Label"), Color.WHITE)
	var reader := ProfileStore.new(_path)
	assert_true(reader.load_profile())
	assert_eq(reader.data["settings"], GameSession.settings.values)


func test_lobby_difficulty_cycles_all_bots_without_replacing_human_seats() -> void:
	var scene: PackedScene = load("res://scenes/menu.tscn")
	var menu: Control = scene.instantiate()
	add_child_autofree(menu)
	menu._mapping = true
	menu._render()
	var found := false
	for button in menu.find_children("*", "Button", true, false):
		if button.text.begins_with("Bots:"):
			button.pressed.emit()
			found = true
			break
	assert_true(found)
	assert_eq(menu._difficulty, 1)
	var controller := RoundController.new(menu.seats)
	for seat in range(4):
		if seat == 2:
			assert_eq(controller.seats[seat]["kind"], "human")
		else:
			assert_eq(controller.seats[seat]["difficulty"], 1)


func test_interruption_freezes_countdown_and_play_without_automatic_resume() -> void:
	for in_play in [false, true]:
		var arena := _arena()
		if in_play:
			arena.controller.run_to_end(3.0)
			assert_eq(arena.controller.state, RoundController.State.PLAYING)
		var timer: float = arena.controller.timer
		var elapsed: float = arena.controller.elapsed
		var ball: Vector2 = arena.controller.rules.ball_position
		var velocity: Vector2 = arena.controller.rules.ball_velocity
		var keeps: Array = arena.controller.rules.keeps.duplicate(true)
		var targets: Array = arena.controller.targets.duplicate()
		var round_index: int = arena.controller.round_index
		arena.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
		arena.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		assert_true(arena.controller.paused)
		assert_true(arena._pause_panel.visible)
		assert_eq(arena.controller.advance(120.0), 0)
		arena._process(0.25)
		var drag := InputEventScreenDrag.new()
		drag.relative = Vector2(100, 0)
		arena._unhandled_input(drag)
		arena.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
		arena.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
		assert_true(arena.controller.paused, "OS focus must not resume play")
		assert_eq(arena.controller.timer, timer)
		assert_eq(arena.controller.elapsed, elapsed)
		assert_eq(arena.controller.rules.ball_position, ball)
		assert_eq(arena.controller.rules.ball_velocity, velocity)
		assert_eq(arena.controller.rules.keeps, keeps)
		assert_eq(arena.controller.targets, targets)
		assert_eq(arena.controller.round_index, round_index)
		arena._set_paused(false)
		assert_gt(arena.controller.advance(0.1), 0)
		if in_play:
			assert_gt(arena.controller.elapsed, elapsed)
		else:
			assert_lt(arena.controller.timer, timer)
		arena.free()


func test_round_over_is_not_restarted_or_paused_by_interruption() -> void:
	var arena := _arena()
	arena.controller.rules.winner = -1
	arena.controller._finish()
	var result: Dictionary = arena.controller.result.duplicate(true)
	arena.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	arena.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	assert_eq(arena.controller.state, RoundController.State.ROUND_OVER)
	assert_false(arena.controller.paused)
	assert_eq(arena.controller.result, result)


func test_restart_restores_eliminated_keep_and_keeps_arena_difficulty() -> void:
	var arena := _arena("diamond")
	arena.controller.rules.keeps[1]["alive"] = false
	arena._on_match_event({"kind": "core", "seat": 1, "wall": -1})
	arena._restart()
	arena._sync_visuals()
	assert_true(arena._shield_nodes[1].visible)
	assert_eq(arena._core_mats[1].albedo_color, ArenaLook.keep_material(1).albedo_color)
	assert_eq(arena.controller.arena_id, "diamond")
	for seat in range(4):
		assert_eq(arena.controller.seats[seat]["difficulty"], GameSession.seats[seat]["difficulty"])
