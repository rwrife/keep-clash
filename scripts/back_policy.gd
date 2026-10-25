class_name BackPolicy
extends RefCounted
## Decides what "back" / window-close mean per screen and platform so the
## behavior is unit-testable without a window manager.
## Screens: "menu", "seats", "round".

const ANDROID := "Android"


static func back_action(screen: String, platform: String, paused: bool) -> String:
	match screen:
		"round":
			return "resume" if paused else "pause"
		"seats":
			return "menu"
		"menu":
			# Android convention: back at the root leaves the app. Desktop confirms.
			return "quit" if platform == ANDROID else "confirm_quit"
	return "none"


static func confirm_leave_round(platform: String) -> bool:
	## Android users expect back/pause to be instant; desktop and iOS confirm
	## before abandoning a round.
	return platform != ANDROID


static func close_request_action(screen: String) -> String:
	## Window close (Windows/desktop X button, Alt+F4). Always confirm; the
	## round scene also pauses first so a stray close cannot lose a round.
	return "pause_and_confirm_quit" if screen == "round" else "confirm_quit"
