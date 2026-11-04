class_name SettingsPanel
extends Control

signal closed

var _capture_action := ""
var _capture_kind := ""
var _status: Label
var _column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color("08131d")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 12)
	scroll.add_child(_column)
	GameSession.settings.changed.connect(_apply_theme)
	_render()


func _apply_theme() -> void:
	theme = GameSession.settings.ui_theme()


func _render() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_apply_theme()
	_label("SETTINGS")
	_label("Changes apply immediately and save locally. Escape always opens pause/back.")
	for key in ["master", "music", "sfx", "hud_scale"]:
		var title := _label(key.capitalize())
		var slider := HSlider.new()
		slider.name = key
		slider.min_value = 0.75 if key == "hud_scale" else 0.0
		slider.max_value = 1.5 if key == "hud_scale" else 1.0
		slider.step = 0.05
		slider.value = float(GameSession.settings.values[key])
		slider.custom_minimum_size.y = 44
		title.text = "%s: %d%%" % [key.capitalize(), roundi(slider.value * 100)]
		slider.value_changed.connect(func(value: float) -> void:
			title.text = "%s: %d%%" % [key.capitalize(), roundi(value * 100)]
			_change(key, value)
		)
		_column.add_child(slider)
	for key in ["reduced_motion", "high_contrast"]:
		var toggle := CheckButton.new()
		toggle.name = key
		toggle.text = key.capitalize()
		toggle.button_pressed = GameSession.settings.values[key]
		toggle.custom_minimum_size.y = 44
		toggle.toggled.connect(func(value: bool) -> void: _change(key, value))
		_column.add_child(toggle)
	_label("CONTROLS (keyboard and per-device gamepad; stick X and touch drag remain available)")
	for action in ["shield_ccw", "shield_cw", "pause"]:
		for kind in ["keys", "buttons"]:
			var binding: Array = GameSession.settings.values["bindings"][action][kind]
			var names := PackedStringArray()
			for code in binding:
				names.append(OS.get_keycode_string(int(code)) if kind == "keys" else "Pad %d" % int(code))
			_button("%s %s: %s" % [action, kind, ", ".join(names)], func() -> void:
				_capture_action = action
				_capture_kind = kind
				_status.text = "Press a %s for %s (Escape cancels)." % ["key" if kind == "keys" else "gamepad button", action]
			)
	_button("Restore default controls", func() -> void:
		_change("bindings", InputSetup.default_bindings())
		_render()
	)
	_status = _label(GameSession.profile.error_message)
	_button("DONE", _close)


func _change(key: String, value: Variant) -> void:
	var settings := GameSession.settings.values.duplicate(true)
	settings[key] = value
	var message := GameSession.update_settings(settings)
	if is_instance_valid(_status):
		_status.text = message


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _capture_action != "":
			_capture_action = ""
			_status.text = "Remapping cancelled."
		else:
			_close()
		get_viewport().set_input_as_handled()
		return
	if _capture_action == "":
		if event.is_action_pressed(InputSetup.ACTION_PAUSE):
			_close()
			get_viewport().set_input_as_handled()
		return
	var code := -1
	if _capture_kind == "keys" and event is InputEventKey and event.pressed and not event.echo:
		if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed:
			_status.text = "Use an unmodified key."
			get_viewport().set_input_as_handled()
			return
		code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	elif _capture_kind == "buttons" and event is InputEventJoypadButton and event.pressed:
		code = event.button_index
	if code < 0:
		return
	var settings := GameSession.settings.values.duplicate(true)
	settings["bindings"][_capture_action][_capture_kind] = [code]
	if not ProfileStore.valid_settings(settings):
		_status.text = "That input is reserved or already assigned. Choose another."
	else:
		var message := GameSession.update_settings(settings)
		_capture_action = ""
		_render()
		_status.text = message
	get_viewport().set_input_as_handled()


func _close() -> void:
	hide()
	closed.emit()
	queue_free()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(label)
	return label


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	_column.add_child(button)
