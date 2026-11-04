extends Node
## Autoload: carries the seat/device configuration from the mapping screen
## into the match scene. Local-first: nothing here touches the network.

var seats: Array[Dictionary] = SeatRouting.make_default_seats()
var match_seed := 31337
var profile := ProfileStore.new()
var settings := SettingsRuntime.new()
var _recorded: Dictionary = {}
var _music_player: AudioStreamPlayer

signal profile_changed


func _ready() -> void:
	get_tree().auto_accept_quit = false
	profile.load_profile()
	settings.apply(profile.data["settings"])
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -18.0
	_music_player.stream = ArenaLook.music_pcm()
	add_child(_music_player)
	_music_player.play()


func _notification(what: int) -> void:
	if not is_instance_valid(_music_player):
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_music_player.stream_paused = true
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_music_player.stream_paused = false


func configure_solo(difficulty: int) -> void:
	seats = SeatRouting.make_solo_seats(difficulty, OS.get_name() in ["Android", "iOS"])


func update_settings(value: Dictionary) -> String:
	if not ProfileStore.valid_settings(value):
		return "Invalid settings or conflicting bindings."
	profile.data["settings"] = value.duplicate(true)
	settings.apply(value)
	persist()
	return profile.error_message


func select_item(kind: String, id: String) -> String:
	var stars := int(profile.data["stars"])
	if kind == "arena":
		if not ArenaCatalog.arena_unlocked(id, stars):
			return "Arena is unknown or needs more stars."
	elif not ArenaCatalog.skin_unlocked(kind, id, stars):
		return "Skin is unknown or needs more stars."
	profile.data["arena" if kind == "arena" else kind + "_skin"] = id
	persist()
	return profile.error_message


func record_round(round_controller: RoundController) -> void:
	if round_controller.state != RoundController.State.ROUND_OVER or round_controller.result.is_empty():
		return
	var key := "%d:%d" % [round_controller.get_instance_id(), round_controller.round_index]
	if _recorded.has(key):
		return
	_recorded[key] = true
	var records: Dictionary = profile.data["records"]
	records["rounds"] = mini(int(records["rounds"]) + 1, ProfileStore.MAX_STARS)
	var winner: int = round_controller.result["winner"]
	if winner >= 0 and round_controller.seats[winner]["kind"] == "human":
		var earned := int(round_controller.result["stars"][winner])
		profile.data["stars"] = mini(int(profile.data["stars"]) + earned, ProfileStore.MAX_STARS)
		records["wins"] = mini(int(records["wins"]) + 1, ProfileStore.MAX_STARS)
		records["best_stars"] = maxi(int(records["best_stars"]), earned)
	persist()


func persist() -> void:
	profile.save_profile()
	profile_changed.emit()
