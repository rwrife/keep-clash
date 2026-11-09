class_name InputSetup
extends RefCounted
## Registers the game's InputMap actions at runtime (idempotent). Keyboard
## actions are key-only on purpose: gamepad seats are read per-device by the
## round scene so two pads never drive the same shield. Settings rewrite these
## same actions; device_strength keeps pad bindings out of keyboard seats.

const ACTION_CW := &"shield_cw"
const ACTION_CCW := &"shield_ccw"
const ACTION_PAUSE := &"pause"
const ACTION_BUMP := &"bump"


static func ensure() -> void:
	_ensure_action(ACTION_CCW, [KEY_A, KEY_LEFT], [])
	_ensure_action(ACTION_CW, [KEY_D, KEY_RIGHT], [])
	_ensure_action(ACTION_PAUSE, [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_ensure_action(ACTION_BUMP, [KEY_SPACE], [JOY_BUTTON_A])


static func default_bindings() -> Dictionary:
	return {"shield_ccw": {"keys": [KEY_A, KEY_LEFT], "buttons": [JOY_BUTTON_LEFT_SHOULDER]},
		"shield_cw": {"keys": [KEY_D, KEY_RIGHT], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
		"pause": {"keys": [KEY_ESCAPE, KEY_P], "buttons": [JOY_BUTTON_START]}}


static func valid_bindings(bindings: Dictionary) -> bool:
	var seen_keys: Array = []
	var seen_buttons: Array = []
	for action in [ACTION_CCW, ACTION_CW, ACTION_PAUSE]:
		var binding: Variant = bindings.get(String(action))
		if not binding is Dictionary:
			return false
		for kind in ["keys", "buttons"]:
			var codes: Variant = binding.get(kind)
			if not codes is Array or codes.is_empty() or codes.size() > 4:
				return false
			for code in codes:
				if not (code is int or code is float) or not is_finite(float(code)) or float(code) != floor(float(code)):
					return false
				var seen: Array = seen_keys if kind == "keys" else seen_buttons
				if code in seen:
					return false
				if kind == "buttons":
					if code < 0 or code >= JOY_BUTTON_MAX:
						return false
				elif OS.get_keycode_string(int(code)).is_empty() or code <= 0 or code >= KEY_UNKNOWN or (code == KEY_ESCAPE and action != ACTION_PAUSE):
					return false
				seen.append(code)
	return true


static func apply_bindings(bindings: Dictionary) -> void:
	assert(valid_bindings(bindings))
	for action in [ACTION_CCW, ACTION_CW, ACTION_PAUSE]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		Input.action_release(action)
		InputMap.action_erase_events(action)
		for code in bindings[String(action)]["keys"]:
			var key := InputEventKey.new()
			key.physical_keycode = int(code)
			InputMap.action_add_event(action, key)
		for code in bindings[String(action)]["buttons"]:
			var pad := InputEventJoypadButton.new()
			pad.button_index = int(code)
			InputMap.action_add_event(action, pad)


static func device_strength(action: StringName, pad: int = -1) -> float:
	for event in InputMap.action_get_events(action):
		if pad < 0 and event is InputEventKey and Input.is_physical_key_pressed(event.physical_keycode):
			return 1.0
		if pad >= 0 and event is InputEventJoypadButton and Input.is_joy_button_pressed(pad, event.button_index):
			return 1.0
	return 0.0


static func _ensure_action(action: StringName, keys: Array, pad_buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	for code in keys:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(action, key)
	for button in pad_buttons:
		var pad := InputEventJoypadButton.new()
		pad.device = -1
		pad.button_index = button
		InputMap.action_add_event(action, pad)
