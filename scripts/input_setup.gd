class_name InputSetup
extends RefCounted
## Registers the game's InputMap actions at runtime (idempotent). Keyboard
## actions are key-only on purpose: gamepad seats are read per-device by the
## round scene so two pads never drive the same shield. Remapping UI (issue #5)
## will rewrite these same actions.

const ACTION_CW := &"shield_cw"
const ACTION_CCW := &"shield_ccw"
const ACTION_PAUSE := &"pause"


static func ensure() -> void:
	_ensure_action(ACTION_CCW, [KEY_A, KEY_LEFT], [])
	_ensure_action(ACTION_CW, [KEY_D, KEY_RIGHT], [])
	_ensure_action(ACTION_PAUSE, [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])


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
		pad.button_index = button
		InputMap.action_add_event(action, pad)
