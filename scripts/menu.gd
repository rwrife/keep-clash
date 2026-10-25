extends Control
## Custom local lobby. Seat claims stay one-device-per-seat before entering play.

const ROUND_SCENE := "res://scenes/round.tscn"
const TEAL := Color("72e0c4")
const INK := Color("142b38")

var seats: Array[Dictionary] = SeatRouting.make_solo_seats(0, OS.get_name() in ["Android", "iOS"])
var _difficulty := 0
var _pending_seat := -1
var _mapping := false
var _message := ""
var _quit_dialog: ConfirmationDialog


func _ready() -> void:
	InputSetup.ensure()
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Quit Keep Clash?"
	_quit_dialog.dialog_text = "Leave the game?"
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	add_child(_quit_dialog)
	_render()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_dialog.popup_centered()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
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
	if _mapping:
		_mapping = false
		_pending_seat = -1
		_render()
	elif BackPolicy.back_action("menu", OS.get_name(), false) == "quit":
		get_tree().quit()
	else:
		_quit_dialog.popup_centered()


func _render() -> void:
	for child in get_children():
		if child != _quit_dialog:
			remove_child(child)
			child.queue_free()
	var background := ColorRect.new()
	background.color = Color("0c1a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(330, 0)
	column.add_theme_constant_override("separation", 13)
	center.add_child(column)
	var title := Label.new()
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


func _render_home(column: VBoxContainer) -> void:
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
		_render()
	)
	_button(column, "QUIT", func() -> void: _quit_dialog.popup_centered())
	_label(column, "A/D or ←/→: steer • Esc/P: pause • drag: touch")


func _render_mapping(column: VBoxContainer) -> void:
	_label(column, "Pick one device per seat; all empty seats become bots.")
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
	label.add_theme_color_override("font_color", Color("bfd8dd"))
	parent.add_child(label)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_color_override("font_color", INK)
	button.pressed.connect(action)
	parent.add_child(button)
