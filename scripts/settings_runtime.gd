class_name SettingsRuntime
extends RefCounted

signal changed

var values: Dictionary = ProfileStore.default_settings()


func apply(settings: Dictionary) -> void:
	assert(ProfileStore.valid_settings(settings))
	values = settings.duplicate(true)
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var index := AudioServer.get_bus_index(pair[0])
		var volume := float(values[pair[1]])
		AudioServer.set_bus_mute(index, volume <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	InputSetup.apply_bindings(values["bindings"])
	changed.emit()


func ui_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = roundi(16.0 * float(values["hud_scale"]))
	var contrast: bool = values["high_contrast"]
	for type in ["Label", "Button", "CheckButton"]:
		theme.set_color("font_color", type, Color.WHITE if contrast else Color("d9edf1"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.BLACK if contrast else Color("183544")
		style.border_color = Color.WHITE if contrast else Color("72e0c4")
		style.set_border_width_all(2 if state != "normal" or contrast else 1)
		style.set_corner_radius_all(6)
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.content_margin_left = 12
		style.content_margin_right = 12
		theme.set_stylebox(state, "Button", style)
	return theme
