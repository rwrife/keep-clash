class_name SeatRouting
extends RefCounted
## Pure seat<->device map used by the mapping screen and match routing.
## One device may hold at most one seat; that invariant is how input
## conflicts are prevented (issue #3 acceptance).

const DIFFICULTY_NAMES := ["Novice", "Steady", "Expert"]


static func make_default_seats() -> Array[Dictionary]:
	var seats: Array[Dictionary] = []
	for _i in range(4):
		seats.append({"kind": "bot", "device": "", "difficulty": 0})
	return seats


static func make_solo_seats(difficulty: int, mobile: bool) -> Array[Dictionary]:
	## Quick-play layout: one human on the bottom seat, three bots.
	var seats := make_default_seats()
	for i in range(seats.size()):
		set_bot(seats, i, difficulty)
	seats[2] = {"kind": "human", "device": "touch" if mobile else "keyboard", "difficulty": -1}
	return seats


static func device_id_for_event(event: InputEvent) -> String:
	## Returns the stable device id for claimable events, "" when the event
	## must not claim a seat (mouse movement, modifiers, confirm keys).
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return ""
		if key.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB]:
			return ""
		return "keyboard"
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if not pad.pressed:
			return ""
		if pad.button_index == JOY_BUTTON_A or pad.button_index == JOY_BUTTON_B:
			return ""
		return "joy_%d" % pad.device
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return ""
		return "touch"
	return ""


static func device_owner(seats: Array[Dictionary], device: String) -> int:
	if device == "":
		return -1
	for i in range(seats.size()):
		if seats[i]["kind"] == "human" and seats[i]["device"] == device:
			return i
	return -1


static func claim(seats: Array[Dictionary], seat: int, device: String) -> String:
	## Returns "" on success or a human-readable refusal reason.
	if device == "":
		return "unrecognized input device"
	if seat < 0 or seat >= seats.size():
		return "no such seat"
	var held := device_owner(seats, device)
	if held == seat:
		return ""
	if held >= 0:
		return "that device already holds seat %d; release it first" % (held + 1)
	if seats[seat]["kind"] == "human":
		return "seat %d is already claimed by %s" % [seat + 1, seats[seat]["device"]]
	seats[seat] = {"kind": "human", "device": device, "difficulty": -1}
	return ""


static func assign_mouse(seats: Array[Dictionary], seat: int) -> String:
	return claim(seats, seat, "mouse")


static func set_bot(seats: Array[Dictionary], seat: int, difficulty: int) -> String:
	if seat < 0 or seat >= seats.size():
		return "no such seat"
	if difficulty < 0 or difficulty > 2:
		return "difficulty must be 0..2"
	seats[seat] = {"kind": "bot", "device": "", "difficulty": difficulty}
	return ""


static func release(seats: Array[Dictionary], seat: int) -> String:
	if seat < 0 or seat >= seats.size():
		return "no such seat"
	seats[seat] = {"kind": "open", "device": "", "difficulty": -1}
	return ""


static func open_seats(seats: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for i in range(seats.size()):
		if seats[i]["kind"] == "open":
			result.append(i)
	return result


static func fill_open_with_bots(seats: Array[Dictionary], difficulty: int = 0) -> void:
	for seat in open_seats(seats):
		set_bot(seats, seat, difficulty)


static func human_count(seats: Array[Dictionary]) -> int:
	var count := 0
	for entry in seats:
		if entry["kind"] == "human":
			count += 1
	return count


static func describe(entry: Dictionary) -> String:
	if entry["kind"] == "bot":
		return "Bot (%s)" % DIFFICULTY_NAMES[entry["difficulty"]]
	if entry["kind"] == "human":
		return "You (%s)" % entry["device"]
	return "Open"


static func duplicate_seats(seats: Array[Dictionary]) -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry in seats:
		copy.append({
			"kind": entry["kind"],
			"device": entry["device"],
			"difficulty": entry["difficulty"],
		})
	return copy
