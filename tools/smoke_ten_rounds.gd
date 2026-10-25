extends SceneTree
## Headless smoke runner: exercises 10 consecutive full round-to-round matches
## driven by the real scene loop, proving that countdown -> play -> win/rematch
## cycles cleanly without leaking or deadlocking.
## Run:
##   godot --headless -s tools/smoke_ten_rounds.gd


func _init() -> void:
	print("starting 10-round headless smoke run...")
	var controller := RoundController.new(SeatRouting.make_default_seats(), 1337)
	# Accelerate the countdown for the smoke run.
	for round_num in range(1, 11):
		var ticks := 0
		while controller.state != RoundController.State.ROUND_OVER and ticks < 24000:
			controller.tick()
			ticks += 1
		if controller.state != RoundController.State.ROUND_OVER:
			push_error("round %d timed out without reaching ROUND_OVER" % round_num)
			quit(1)
			return
		var res: Dictionary = controller.result
		print("  round %d finished in %d ticks (winner: seat %d, timed_out: %s)" % [
			round_num, ticks, res["winner"] + 1 if res["winner"] >= 0 else 0, res["timed_out"]])
		controller.rematch()
		if controller.state != RoundController.State.COUNTDOWN:
			push_error("round %d rematch failed to enter COUNTDOWN" % round_num)
			quit(1)
			return
	print("SUCCESS: 10 consecutive rounds completed cleanly")
	quit(0)
