extends Control
## Custom local lobby. Seat claims stay one-device-per-seat before entering play.

const ROUND_SCENE := "res://scenes/round.tscn"
const TEAL := Color("72e0c4")

var seats: Array[Dictionary] = SeatRouting.make_solo_seats(0, OS.get_name() in ["Android", "iOS"])
var _difficulty := 0
var _pending_seat := -1
var _mapping := false
var _message := ""
var _quit_dialog: ConfirmationDialog
var _settings_panel: SettingsPanel
var _title: Label
var _background: ColorRect
var _backup_dialog: FileDialog
var _backup_open := false


func _ready() -> void:
	InputSetup.ensure()
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Quit Keep Clash?"
	_quit_dialog.dialog_text = "Leave the game?"
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	add_child(_quit_dialog)
	_backup_dialog = FileDialog.new()
	_backup_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_backup_dialog.use_native_dialog = true
	_backup_dialog.filters = PackedStringArray(["*.json ; Keep Clash JSON backup"])
	_backup_dialog.file_selected.connect(_backup_selected)
	_backup_dialog.canceled.connect(func() -> void:
		_backup_open = false
		_message = "Backup selection canceled; no files changed."
		_render()
	)
	add_child(_backup_dialog)
	GameSession.settings.changed.connect(_apply_theme)
	_render()


func _apply_theme() -> void:
	theme = GameSession.settings.ui_theme()
	var contrast: bool = GameSession.settings.values["high_contrast"]
	if is_instance_valid(_title):
		_title.add_theme_color_override("font_color", Color.WHITE if contrast else TEAL)
	if is_instance_valid(_background):
		_background.color = Color.BLACK if contrast else Color("0c1a27")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _backup_open:
			_quit_dialog.popup_centered()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if _backup_open or is_instance_valid(_settings_panel):
		return
	if _pending_seat >= 0:
		var device := SeatRouting.device_id_for_event(event)
		if device != "":
			_message = SeatRouting.claim(seats, _pending_seat, device)
			_pending_seat = -1
			_render()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(InputSetup.ACTION_PAUSE):
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	if _backup_open:
		return
	if is_instance_valid(_settings_panel):
		_settings_panel._close()
	elif _mapping:
		_mapping = false
		_pending_seat = -1
		_render()
	elif BackPolicy.back_action("menu", OS.get_name(), false) == "quit":
		get_tree().quit()
	else:
		_quit_dialog.popup_centered()


func _render() -> void:
	_apply_theme()
	for child in get_children():
		if child != _quit_dialog and child != _backup_dialog:
			remove_child(child)
			child.queue_free()
	var background := ColorRect.new()
	_background = background
	background.color = Color("0c1a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(300, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 13)
	center.add_child(column)
	var title := Label.new()
	_title = title
	title.text = "KEEP CLASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TEAL)
	title.add_theme_font_size_override("font_size", 42)
	column.add_child(title)
	_label(column, "Offline • four keeps • one orb")
	if _mapping:
		_render_mapping(column)
	else:
		_render_home(column)
	if _message != "":
		_label(column, _message)
	if GameSession.profile.error_message != "":
		_label(column, GameSession.profile.error_message)
	_apply_theme()


func _render_home(column: VBoxContainer) -> void:
	var profile: Dictionary = GameSession.profile.data
	_label(column, "%d stars earned | %d wins / %d rounds" % [
		profile["stars"], profile["records"]["wins"], profile["records"]["rounds"]])
	_button(column, "SOLO ROUND", func() -> void:
		seats = SeatRouting.make_solo_seats(_difficulty, OS.get_name() in ["Android", "iOS"])
		_start()
	)
	_button(column, "SEAT MAPPING / COUCH PLAY", func() -> void:
		_mapping = true
		_render()
	)
	_button(column, "Bot difficulty: %s" % SeatRouting.DIFFICULTY_NAMES[_difficulty], func() -> void:
		_difficulty = (_difficulty + 1) % 3
		for seat in range(4):
			if seats[seat]["kind"] == "bot":
				SeatRouting.set_bot(seats, seat, _difficulty)
		_render()
	)
	for id in ArenaCatalog.IDS:
		var arena: Dictionary = ArenaCatalog.ARENAS[id]
		var unlocked := ArenaCatalog.arena_unlocked(id, int(profile["stars"]))
		var button := _button(column, "%s%s%s" % [
			"> " if profile["arena"] == id else "", arena["name"],
			"" if unlocked else " (needs %d stars)" % arena["stars"]], func() -> void:
			_message = GameSession.select_item("arena", id)
			_render()
		)
		button.disabled = not unlocked
		if profile["arena"] == id:
			_label(column, arena["description"])
	for kind in ["shield", "keep"]:
		for id in ArenaCatalog.SKINS[kind]:
			var unlocked := ArenaCatalog.skin_unlocked(kind, id, int(profile["stars"]))
			var button := _button(column, "%s%s: %s%s" % [
				"> " if profile[kind + "_skin"] == id else "", kind.capitalize(), id.capitalize(),
				"" if unlocked else " (needs %d stars)" % ArenaCatalog.SKINS[kind][id]], func() -> void:
				_message = GameSession.select_item(kind, id)
				_render()
			)
			button.disabled = not unlocked
	_button(column, "SETTINGS", func() -> void:
		_settings_panel = SettingsPanel.new()
		_settings_panel.closed.connect(_render)
		add_child(_settings_panel)
	)
	_button(column, "EXPORT BACKUP", func() -> void: _show_backup(false))
	_button(column, "IMPORT BACKUP (REPLACE PROFILE)", func() -> void: _show_backup(true))
	_button(column, "QUIT", func() -> void: _quit_dialog.popup_centered())
	var keys := PackedStringArray()
	for code in GameSession.settings.values["bindings"]["shield_cw"]["keys"]:
		keys.append(OS.get_keycode_string(int(code)))
	_label(column, "Steer right: %s | Escape: pause | drag: touch" % ", ".join(keys))


func _show_backup(importing: bool) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_message = "Native file dialogs are unavailable on this platform; no files changed."
		_render()
		return
	_backup_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if importing else FileDialog.FILE_MODE_SAVE_FILE
	_backup_dialog.title = "Import backup - replace all settings and progress" if importing else "Export Keep Clash backup"
	_backup_dialog.current_file = "" if importing else "keep-clash-backup.json"
	_backup_open = true
	_backup_dialog.popup_centered_ratio(0.8)


func _backup_selected(selected_path: String) -> void:
	_backup_open = false
	if _backup_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		var failure: String = GameSession.import_profile(selected_path)
		_message = "Backup imported; settings and progress restored." if failure == "" else failure
	else:
		_message = "Backup exported to %s" % selected_path if GameSession.profile.export_profile(selected_path) else GameSession.profile.error_message
	_render()


func _render_mapping(column: VBoxContainer) -> void:
	_label(column, "Pick one device per seat; all empty seats become bots.")
	_button(column, "Bots: %s (cycle)" % SeatRouting.DIFFICULTY_NAMES[_difficulty], func() -> void:
		_difficulty = (_difficulty + 1) % 3
		for seat in range(4):
			if seats[seat]["kind"] == "bot":
				SeatRouting.set_bot(seats, seat, _difficulty)
		_render()
	)
	for seat in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var info := Label.new()
		info.text = "%d · %s" % [seat + 1, SeatRouting.describe(seats[seat])]
		info.custom_minimum_size.x = 155
		row.add_child(info)
		var seat_id := seat
		_button(row, "CHANGE", func() -> void: _seat_popup(seat_id))
		_button(row, "BOT", func() -> void:
			SeatRouting.set_bot(seats, seat_id, _difficulty)
			_message = ""
			_render()
		)
	_button(column, "PLAY LOCAL ROUND", func() -> void: _start())
	_button(column, "BACK", func() -> void:
		_mapping = false
		_render()
	)


func _seat_popup(seat: int) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Seat %d device" % (seat + 1)
	dialog.dialog_text = "Select a device. Keyboard and mouse are separate input sources; one human per source."
	for option in ["Keyboard", "Mouse", "Touch", "Gamepad (press D-pad / shoulder)", "Open (bot at play)"]:
		dialog.add_button(option, true, option)
	dialog.custom_action.connect(func(action: StringName) -> void:
		var device := String(action).to_lower()
		if device.begins_with("gamepad"):
			_pending_seat = seat
			_message = "Press D-pad or shoulder on the gamepad for seat %d" % (seat + 1)
		elif device.begins_with("open"):
			_message = SeatRouting.release(seats, seat)
		else:
			_message = SeatRouting.claim(seats, seat, device)
		dialog.hide()
		dialog.queue_free()
		_render()
	)
	dialog.close_requested.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _start() -> void:
	SeatRouting.fill_open_with_bots(seats, _difficulty)
	if SeatRouting.human_count(seats) == 0:
		_message = "Claim at least one seat before playing."
		_render()
		return
	GameSession.seats = SeatRouting.duplicate_seats(seats)
	get_tree().change_scene_to_file(ROUND_SCENE)


func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
