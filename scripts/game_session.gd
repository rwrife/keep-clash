extends Node
## Autoload: carries the seat/device configuration from the mapping screen
## into the match scene. Local-first: nothing here touches the network.

var seats: Array[Dictionary] = SeatRouting.make_default_seats()
var match_seed := 31337


func _ready() -> void:
	get_tree().auto_accept_quit = false


func configure_solo(difficulty: int) -> void:
	seats = SeatRouting.make_solo_seats(difficulty, OS.get_name() in ["Android", "iOS"])
